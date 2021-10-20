;**********************************************************************
;                                                                     *
;    Filename: VFD Main.asm                                           *
;    Date:     21/12/2017                                            *
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

; five bytes are required to hold the 40 display bits
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
AuxInd		EQU		0x2D		;aux indicators and PAB00 

;demo control variables
TestVal		EQU		0x2E		;value is ramped up to 100 then down to 0 in a loop
Mode		EQU		0x2F		;display mode changes after each ramp
Control		Equ		0x30		;control bits
;control bits
RampDwn		equ		0		;count up/dwn flag
SwtDBB		equ		1		;switch debounce bit



Temp0		EQU		0x70		;temp bytes for normal routines
Temp1 		EQU		0x71
Randlo		EQU		0x72		;random shift reg
RandHI		EQU		0x73
Intemp0		EQU		0x79		;temp bytes for interrupt routines
Intemp1		EQU		0x7A


;**********************************************************************
	    ORG     0x000             ; processor reset vector

	    ;nop
	    ;pagesel	main
	    goto    main              ; go to beginning of program


	    ORG     0x004             ; interrupt vector location
; isr code can go here or be located as a call subroutine elsewhere
	    btfss	INTCON,T0IF			;test timer 0 interrupt	
	    goto	intxit
	    bcf		INTCON,T0IF			;clear the interrupt flag
	    ;call	DoFrm
	    call	setTimer

intxit	    retfie                    ; return from interrupt

;==========================================< Tables >=======================================
;------Anode value table
;This holds the initial value for the anodes in the current frame (faster than multiplying on the fly) 
AnVTab	    BRW
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
 
GrdTabL	    BRW
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
	
GrdTabH	    BRW
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
	    banksel	OSCCON
	    ;movlw	B'11110000' ;32Mhz clock
	    ;movlw	B'01111010' ;16Mhz clock
	    ;movlw	B'01110010' ;8Mhz clock
	    movlw	B'01101010' ;4Mhz clock
	    movwf	OSCCON
	    
	    ;initialise analogue ports
	    
	    banksel	ANSELA 	;select the correct bank
	    clrf	ANSELA	;clear the analog selects (all digital inputs)
	    
	    ;initialise O/P pins
	    banksel	TrisA
	    movlw	B'00000011' ;RA0 & RA1 & RA3 inputs
	    movwf	TrisA	;port A all outputs
	    
	    ;initislise EUSART
	    call	InitUART 

	    ;initialise timer
	    banksel	Option_Reg
	    movlw	B'00000001'	;Timer0 via 1:4 prescaler 
	    movwf	Option_Reg
	    call	setTimer		


	    ;initialise interrupts
	    banksel	INTCON
	    movlw	B'10100000'	;enable TOIE - disable interrupt if calling dofrm from mainloop
	    movwf	INTCON
	    

	    ;seed random gen
	    movlw	0x30
	    movwf	Randhi
	    movlw	0x45
	    movwf	Randlo
	    ;clear variables
	    clrf	BonVl
	    clrf	BoffVl
	    clrf	DotVl
	    clrf	BonVr
	    clrf	BoffVr
	    clrf	DotVr
	    clrf	AuxInd
	    clrf	mode
	    clrf	control
	    clrf	testval
;==================================< main loop >===================================
;
mainlp:
	    decfsz	temp0,f
	    goto	mainlp		;delay to slow main loop
	    movlw	0x40		
	    movwf	temp0
	    call 	dofrm		;doframe can be called here instead of interrupt
	    
	    decfsz	temp1,f
	    goto	mainlp
	    movlw	.19		;
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
DoMode:
	    rrf		mode,w			
	    andlw	0x07		
	    addwf	PCL,f
	    goto	ConvBar		;do conventional bar display
	    goto	Indbar
	    goto	InvBar		;do inverted bar
	    goto	TrendBar	;do trend bar
	    goto	SimpleDot	;do dot display
	    goto	CentreDot	;dot display with centre line
	    goto	peakbar		;bar with peak dot
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
	    bcf		AuxInd,PAB00	;switch off the bottom pair
	    clrf	dotvl
	    clrf	dotvr	
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

;dot display 
SimpleDot:
	    clrf	bonvl
	    clrf	bonvr
	    clrf	boffvl
	    clrf	boffvr
	    bcf		AuxInd,PAB00	;switch off the bottom pair	
	    movf	testval,w	
	    movwf	dotvl
	    sublw	.100
	    movwf	dotvr		
	    return
CentreDot:
	    movlw	.50
	    movwf	bonvl
	    movwf	bonvr
	    movlw	.51
	    movwf	boffvl
	    movwf	boffvr
	    bcf		AuxInd,PAB00	;switch off the bottom pair	
	    movf	testval,w	
	    movwf	dotvl
	    movwf	dotvr		
	    return

PeakBar:    clrf	bonvl
	    clrf	bonvr
	    decf	BoffVl,f	;do decay
	    decf	BoffVr,f
	    movf	testval,w
	    btfss	status,z	;clear peak on second run
	    goto	pkrnd
	    clrf	dotvl
	    clrf	dotvr

pkrnd	    movf	randhi,w	;get random-ish value
	    andlw	0x3f		;0-63
	    subwf	boffVl,w	;compare with current peak
	    btfsc	status,c
	    goto	pkright
	    movf	Randhi,w
	    andlw	0x3f		;0-63
	    movwf	boffvl		;set new peak


	    movf	randhi,w	;get random-ish value
	    andlw	0x3f		;0-63
	    subwf	dotVl,w	;compare with current peak
	    btfsc	status,c
	    goto	pkright
	    movf	Randhi,w
	    andlw	0x3f		;0-63
	    movwf	dotvl

pkright	    movf	Randlo,w	;get random-ish value
	    andlw	0x3f
	    subwf	boffVr,w	;compare with current peak
	    btfsc	status,c
	    return
	    movf	randlo,w
	    andlw	0x3f		;0-63
	    movwf	boffvr		;set new peak	


	    movf	Randlo,w	;get random-ish value
	    andlw	0x3f
	    subwf	dotVr,w		;compare with current peak
	    btfsc	status,c
	    return
	    movf	randlo,w
	    andlw	0x3f		;0-63
	    movwf	dotvr			;set new peak			
	    return



;----------------------------------------------------------------------------------


; remaining code goes here



;VFD display routines called from timer interrupt or main loop

setTimer: 	;used if dofrm is called from interrupt only
	    banksel	TMR0
	    movlw	0xc0	;frame rate is 19frames * 20 scans/second 
	    movwf	TMR0	;set timer	
	    return	

DoFrm:
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
	    goto	tstODD		;goto test Odd frame. 
				;Odd frames have two grids & set PAB10

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

	    movf	Auxind,w		;get LED indicator switches
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

	    decfsz	intemp0,f
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
	       
	    Banksel	SPBRGH
	    clrf	SPBRGH
	    movlw	0x00
	    movwf	SPBRGL
	    
	    Banksel	APFCON	    ;set alt pins
	    movlw	B'10000100'
	    movwf	APFCON
	    
	    Banksel	BAUDCON
	    movlw	B'00011000'
	    movwf	BAUDCON
	    
	    Banksel	TXSTA	    ;set tx control
	    movlw	B'10110000'
	    movwf	TXSTA
	    
	    Banksel	RCSTA
	    movlw	B'10000000' ;enable USART
	    movwf	RCSTA

	    return
	    
Shftout: 
	    Banksel	PortA
	    bcf		disport,latch  
	    movlw	PB29
	    movwf	FSR0L	    ;set indirection pointer
	    clrf	FSR0H
	    
	    movlw	0x05	    ;set byte counter
	    movwf	intemp0
waitTXF:  
	    ;Banksel	TXSTA
	    ;btfss	TXSTA,TRMT	    
	    ;goto	waitTXF	    ;wait for buffer clear
	    banksel	TXREG
	    movf	INDF0,w	    ;get byte at pointer
	    movwf	TXREG	    ;output to shifter
	    incf	FSR0L,f	    ;increment pointer
	    Banksel	TXSTA
waitlst     btfss	TXSTA,TRMT	    
	    goto	waitlst	    ;wait for last buffer clear	    
	    decfsz	intemp0,f   ;decrement counter
	    goto	waitTXF	    ;loop 5 bytes out	    
	    Banksel	PortA
	    bsf		disport,latch  

	    return
	    
	    END                       ; directive 'end of program'


