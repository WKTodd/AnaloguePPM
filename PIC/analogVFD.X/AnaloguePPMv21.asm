;**********************************************************************
;                                                                     *
;    Filename: VFD Main.asm                                           *
;    Date:     17/09/1991 to 26/11/2020                               *
;    File Version:      2.0                                           *
;                                                                     *
;    Author:             W.K.Todd                                     *
;    Company:            Todd Electronics                             *
;                                                                     * 
;                                                                     *
;**********************************************************************
;                                                                     *
;    Files Required: P16F1572.INC                                     *
;                                                                     *
;**********************************************************************

;**********************************************************************
; The display is multiplexed one frame at a time, by taking a grid
; (or pair of grids) high (output 1) and the anodes low for off or high for on
;
; In order to ensure even brightness at the ends of the grids, the 
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

#include "p12f1572.inc"

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


;bit value for the GRD810 display byte
IND1		EQU		7			;Aux LED1 (GRD810.7)
IND2		EQU		6			;Aux LED2 (GRD810.6)
IND3		EQU		5			;Aux LED3 (GRD810.5)
IND4		EQU		4			;Aux LED4 (GRD810.4)
IND5		EQU		3			;Aux LED5 (GRD810.3)
PAB00		EQU		0			;Bottom pair of segments (Grd17.0)
		
;bytes used by display routine to keep place
FrmNo		EQU		0x25		;Bits 0-5 Current frame number [0=bottom 19=top], bit6-7
AnVal		EQU		0x26		;Current anode value [1-100]
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
DecCnt		EQU		0x30		;decay rate counter
Mode		EQU		0x31		;display mode 		
RefCnt		EQU		0x32		;Ref bar Dimmer control counter
PKHTMR		EQU		0x33		;peak hold timer (dec at field rate)
HmSec		EQU		0x34		;Hundred millisecond counter (incremented @ 10Hz)
FrmCnt		EQU		0x35		;frame count for half sec timer	
SwtDBV		EQU		0x36		;switch debounce etc.		
SwtDBT		EQU		0x37		
	
;PPM prefs 16 bytes 0x40-0x4F (saved to Flash @ 0x780-0x78F as RETLW 0xXX )
PREFS		EQU		0x40		
PkHOpt		EQU		0x40		;Peak Hold Option off,1s,3s,hold 
DecOpt		EQU		0x41		;Decay rate  opt slo2,med,med,high
RefLvl		EQU		0x42		;Reference level
DCPldL		EQU		0x43		;DC offset preload value
DCPldH		EQU		0x44		
DCOmd		EQU		0x45		;DC offset mode
;DCOmd bits
DCaut		EQU		7		;auto enable		
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
		
DcFtL0		EQU		0x30	;Dc filter array Left
DcFtL1		EQU		0x31	;
DcFtL2		EQU		0x32	;
DFCntL		EQU		0x33	; loop counter
		
DcFtR0		EQU		0x34	;Dc filter array right
DcFtR1		EQU		0x35	; 
DcFtR2		EQU		0x36	;
DfCntR		EQU		0x37	; loop counter
		
DCOSL		EQU		0x38	;dc offset value
DCOSR		EQU		0x39	
		
;Common RAM (16 bytes   0x70 - 0x7F)		
Temp0		EQU		0x70		;temp bytes for normal routines
Temp1 		EQU		0x71
Intemp0		EQU		0x72		;temp bytes for interrupt routines
Intemp1		EQU		0x73
FrmTmr		EQU		0x74		;frame timer (decremented by TO int) 
Phase		EQU		0x75		;phase counter for DC filter		
DCRldL		EQU		0x76		;DC offset adjust ing pulse  value
DCRldH		EQU		0x77		
DCTmr		EQU		0x78		;timer for above

Control		Equ		0x7F		;control bits
;Control bits
RampDwn		equ		0		;count up/dwn flag
SwtMode		equ		1		;mode switch debounce bit
SwtSP		equ		2		;short press switch
SwtLP		equ		3		;long press switch
		
ADCch		equ		6		;analogue input 0=right 1=left
RefEn		equ		7		;display flag for ref marker dimmer


;**********************************************************************
	    ORG     0x000             ; processor reset vector

	    goto    main              ; go to beginning of program


	    ORG     0x004             ; interrupt vector location
; isr code can go here or be located as a call subroutine elsewhere
AdInt:
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
	    
	    
	    btfsc	Control,ADCch	;test channel and toggle
	    bra		saveLch
	    bsf		Control,ADCch	;toggle input to left ch
	    
;save  Right channel and test peak
	    movwf	ARinH		;save left channel bits 9-2
	    movf	ADRESL,w	;save lower two bits 1-0
	    movwf	ARinL
	    lslf	ARinL,w		;get bit 1 into carry
	    rlf		ARinH,w		;get sign bit (9) into carry and 8-1 into w
	    btfss	status,c	;test sign bit
	    bra		posright
	    xorlw	0xff		;rectify
	    addlw	0x01		;add 1 so -1 = 1
posright    movwf	Ptemp		;save for later
	    subwf	PRinH,w		;compare with Peak value
	    btfsc	status,c	
	    bra		xitPR		;Input < Peak we're done

	    
newPR	    ;movf	DCOSR,w
	    ;subwf	Ptemp,w
	    movf	Ptemp,w
	    movwf	PRinH		;save new peak   	    

	    
	    bra		xitPR
	    
	    
saveLch	    bcf		Control,ADCch	;toggle channel to right ch
	    movwf	ALinH		;save left channel
	    movf	ADRESL,w
	    movwf	ALinL
	    
	    lslf	ALinL,w		;get bit 1 into carry
	    rlf		ALinH,w		;get sign bit (9) into carry and 8-1 into w
	    btfss	status,c	;test sign bit
	    bra		Posleft
	    xorlw	0xff		;rectify
	    addlw	0x01
posleft	    movwf	Ptemp
	    subwf	PLinH,w		;compare with Peak value
	    btfsc	status,c	
	    bra		xitPL		;Input < Peak we're done

	    
newPL	    ;movf	DCOSL,w
	    ;subwf	Ptemp,w
	    movf	Ptemp,w
	    movwf	PLinH		;save new peak 

xitPL	    
xitPR	    ;
	    banksel	ADCON0		;bank1
	    btfss	ADRESH,7		;
	    bra		doneg
	    decfsz	Phase,f
	    bra		intT0
	    incf	Phase,f		;dec down to 1
	    bra		intT0
doneg	    incfsz	Phase,f
	    bra		intT0
	    comf	Phase,f		;inc phase to FF
	    
	    
intT0:	    btfss	INTCON,T0IF	    ;test timer 0 interrupt	
	    bra		intxit
	    bcf		INTCON,T0IF	    ;clear the interrupt flag
	    decf	FrmTmr,f	    ;clock frame timer
	    ;call	setTimer
	    banksel	TMR0
	    movlw	.255 - (.8*.17) 	;osc/4 17us 
	    movwf	TMR0	;set timer	
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
	    
	    ;initialise timer
	    banksel	Option_Reg
	    movlw	B'10001000'	;Timer0 no prescale osc/4, WPU off
	    movwf	Option_Reg	
;	    call	setTimer	
	    
	    ;initialise analogue ports
	    banksel	FVRCON		;BANK 2  
	    ;movlw	B'10000011'	;FVR for ADC ref set to 4.096v
	    movlw	B'10000010'	;FVR for ADC ref set to 2.048v
	    ;movlw	B'10000001'	;FVR for ADC ref set to 1.024v
	    movwf	FVRCON
	    
	    banksel	ANSELA		;select bank 3
	    movlw	B'00000011'	;
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
	    banksel	TrisA		;BANK 1
	    movlw	B'00001011'	;RA0 & RA1 & RA3 inputs
	    movwf	TrisA		;port A i/o set
	    banksel	PortA
	    movlw	B'11111111'
	    movwf	PortA
	    
	    
	    Banksel	APFCON	    ;set alt pins
	    movlw	B'10000100' ;TX/RX 
	    movwf	APFCON
		    	       
	    
	    ;initislise EUSART
	    call	InitUART 
	    
initpwm:
	    ;initialise pwm1 for DC offset adjustment
;	    banksel	PWM3CON
;	    movlw	B'01000001'	;no prescale, Fosc HFintosc	    
;	    movwf	PWM3CLKCON	;pwm clock control
;	    movlw	B'00000000'	;enable module standard mode
;	    movwf	PWM3CON		;used for Step out pin RA4
;
;	    movlw	B'00000001'
;	    movwf	PWM3LDCON	;PWM load control
;	   
;	    movwf	PWM3OFCON	;offset control 
;	    clrw
;	    movwf	PWM3PHL
;	    movwf	PWM3PHH
;	    movwf	PWM3OFL
;	    movwf	PWM3OFH
;	    movwf   	PWM3TMRH	;timer register Hi	    
;	    movwf	PWM3TMRL
;	    movlw	HIGH 12800	;400uS
;	    movwf	PWM3PRH		;period count Hi
;	    movlw	LOW 12800
;	    movwf	PWM3PRL		;period count Lo
;	    movlw	HIGH 3840	;120uS
;	    movwf	PWM3DCH		;Duty cycle Hi 
;	    movlw	LOW 3840
;	    movwf	PWM3DCL		;Duty cyle Lo 
;	    clrf	PWM3INTF

;	    bsf		PWM3CON,EN
;	    bsf		PWM3LDCON,LDA 
;	    bsf		PWM3CON,OE

	    

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
setvariables:
	    ;clear variables
	    call	clrall
	    clrf	mode
	    clrf	control
	    ;movlw	.2
	    call	FPRTab
	    movwf	PkHOpt	    ;set default peak hold time
	    clrf	PKHTMR
	    clrf	HmSec
	    ;movlw	.2	    ;deacy option 2 medium-slow
	    call	FPRTab+1
	    movwf	DecOpt	    ;set default decay rate
	    ;movlw	.75	    ;set default reference level marker (0dB)
	    call	FPRTab+2
	    movwf	RefLvl
	    call	FPRTab+3    ;DCpreload value
	    movwf	DCRldL
	    call	FPRTab+4
	    movwf	DCRldH	
	    call	FPRTab+5    ;DC mode bits
	    movwf	DCOmd
	    
;==================================< main loop >===================================
;
mainlp:	    
	    call	DoFrmSlot	;do one frame slot 
	    call 	dofrm		;do next frame
synclp	    btfss	FrmTmr,7	;check for timer roll over
	    bra		synclp
	    movlw	.20
	    movwf	FrmTmr
	    call	Shftout
 	    goto	mainlp
;--------------------------------------------------------------------------------

DoFrmSlot:  movf	FrmNo,w	    ;do one of 19x 250uS slots between frames
	    brw
	    goto	DoHmSC		;0 do 100mS counter
	    goto	DoMode		;1 do display mode
	    goto	DoDecay		;2
	    goto	ClrPeak		;3  
	    return			;4
	    return			;5
	    return			;7
	    return			;8	    
	    return			;9 
	    goto	DCOffset	;10 do dc offset adjust
	    return			;11
	    return			;12	    
	    return			;13
	    return			;14	    
	    return			;15	    
	    return			;16
	    return			;17	    
	    return			;18
	    goto	DoSwitch	;19 do switch routine
	    
DoMode:	    movf	Mode,w
	    andlw	0x07
	    brw
	    goto	PeakBar		;mode 0 - peakbar
	    goto	SetDecay	;mode 1 - set decay rate
	    goto	SetPkCl		;mode 2 - set peak hold times
	    goto	SetDCO		;mode 3 - DC adjust
	    goto	PrfSave		;mode 4 - save prefs
	    clrf	Mode		;mode 5 - reset mode to 0 
	    clrf	Mode		;mode 6 - reset mode to 0
RSMode	    clrf	Mode		;mode 7 - reset mode to 0
	    return
	    
;do switch routines
DoSwitch:   
	    banksel	PortA
	    btfss	PortA,Switch
	    bra		dopress
	    decfsz	SwtDBT,f
	    return
	    btfsc	Control,SwtMode
	    bsf		Control,SwtSP	    ;set short press on release of key
	    bcf		Control,SwtMode	    ;clear mode switch bit
	    return
	    
dopress	   
	    btfsc	Control,SwtMode
	    bra		dohld
	    movlw	.16
	    movwf	SwtDBT
	    bsf		Control,SwtMode	    ;set mode switch bit
	    movf	HmSec,w		    ;get 100mS timer value
	    addlw	.20		    ;add 3seconds
	    movwf	SwtDBV		    ;save timer
	    ;bsf		Control,SwtSP	    ;set short press flag (cleared by routine)
	    return

dohld	    movf	SwtDBV,w
	    xorwf	HmSec,w
	    btfss	status,z	;test if halfsecv = swtdbv 
	    return
	    ;long press routine here
	    movf	HmSec,w		    ;get 100mS timer value
	    addlw	.20		    ;add 3seconds
	    movwf	SwtDBV		    ;save timer
	    bsf		Control,SwtLP
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
	    btfss	Control,SwtLP
	    return
	    bcf		Control,SwtLP
	    bcf		Control,SwtSP
	    incf	Mode,f
	    return


	    ;analogue peak linear bar
ManPkClr    call	manclr		;manual clear peak
	    bcf		Control,SwtSP	;clear button flag
	    
PeakBar:    btfsc	Control,SwtSP
	    bra		manPkClr
	    btfss	Control,SwtLP
	    bra		disppb
	    incf	Mode,f
	    bcf		Control,SwtLP
	    return
	    
disppb	    clrf	bonvl
	    clrf	bonvr
	    movf	RefLvl,w        ;0dB marker for current scale
	    movwf	RefVl
	    movwf	RefVr
	    bsf		AuxInd,PAB00	;bottom segments on



pkleft	    
	    movlb	1		;bank 1
	    movf	PLinH,w		;get current peak
	    sublw	FSD
	    btfss	status,c
	    bra		OverL
	    movf	PLinH,w		;get current peak
	    clrf	PLinH		;and clear
	    movlb	0
	    call	ScaleTab	;scale in w 
	    movwf	Temp1		;save for later
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
	    
	    
OverL	    clrf	PLinH		;and clear
	    movlb	0 
	    bsf		AuxInd,IND1
	    movlw	.100
	    movwf	BoffVl
	    movwf	DotVl
	 

	    
pkright	    
	    movlb	1		;bank 1
	    movf	PRinH,w		;get current peak
	    sublw	FSD
	    btfss	status,c
	    bra		OverR
	    movf	PRinH,w		;get current peak
	    clrf	PRinH		;and clear
	    movlb	0
	    call	ScaleTab	;scale in w 
	    movwf	Temp1           ;and save in Temp1
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
	    
OverR	    clrf	PRinH		;and clear
	    movlb	0
	    bsf		AuxInd,IND2
	    movlw	.100
	    movwf	BoffVr
	    movwf	DotVr
	    return

SetDecay:   ;set decay speed mode  
	    bcf		AUXInd,PAB00	;bottom segments off 
	    clrf	Refvl
	    clrf	Refvr		;ref dots off
	    clrf	DotVl
	    clrf	DotVr
	    movlw	.65		;pulse value 
	    movf	BoffVl,f	;test boffvl
	    btfsc	status,z
	    movwf	BoffVl
	    movf	DecOpt,w	;get decay speed option 0-3
	    call	DisOpt		;set right bar to display option
	    btfss	Control,SwtSP
	    bra		tstSLP
	    bcf		Control,SwtSP	;do next option
	    incf	DecOpt,f
	    movf	DecOpt,w
	    andlw	0x03
	    movwf	DecOpt	    
tstSLP	    btfss	Control,SwtLP
	    return
	    bcf		Control,SwtLP
	    bcf		Control,SwtSP
	    incf	Mode,f
	    return

	    
DisOpt:	    ;display option on right bar
	    andlw	0x03
	    call	OBtab
	    movwf	BonVr
	    addlw	.25
	    movwf	BoffVr
	    return    
	    
OBtab	    brw
	    retlw	.1	;opt bar at bottom
	    retlw	.25
	    retlw	.50
	    retlw	.75
	    
DoDecay:    decfsz	DecCnt,f	;decrement bar 
	    return
	    movf	DecOpt,w
	    call	DecTab
	    movwf	DecCnt
	    movf	BoffVl,w
	    btfss	status,z
	    decf	BoffVl,f	;do decay if >0
	    movf	BoffVr,w
	    btfss	status,z	    
	    decf	BoffVr,f
	    return
	    
Dectab	    andlw	0x03
	    brw
	    retlw	.7	    ;opt 0 slow	~4.8mS / seg
	    retlw	.5	    ;opt 1 med slow
	    retlw	.3	    ;opt 2 med-fast
	    retlw	.1	    ;opt 3 fast ~400uS/seg
	    
SetPkCl:    ;set peak clear/hold options
	    bcf		AUXInd,PAB00	;bottom segments off 
	    clrf	Refvl
	    clrf	Refvr		;ref dots off
	    clrf	BoffVl
	    movf	HmSec,w
	    andlw	0x3f		;random-ish number
	    addlw	.10		;offset it
	    movf	DotVl,f
	    btfsc	status,z
	    movwf	DotVl
	    movf	PkHOpt,w	;get peakhold speed option 0-3
	    call	DisOpt		;set right bar to display option
	    btfss	Control,SwtSP
	    bra		tstPLP
	    bcf		Control,SwtSP	;do next option
	    incf	PkHOpt,f
	    movf	PkHOpt,w
	    andlw	0x03
	    movwf	PkHOpt	    
tstPLP	    btfss	Control,SwtLP
	    return
	    bcf		Control,SwtLP
	    bcf		Control,SwtSP
	    incf	Mode,f
	    return
	    
	    
	    
ClrPeak:    movf	PkHOpt,w
	    btfsc	status,z	;test if option 0 off
	    bra		pkoff
	    xorlw	0x03		;test if option 3 hold
	    btfss	status,z
	    bra		pkclr
	    
	    movf	HmSec,w		;set PK timer
	    movwf	PKHTMR
	    incf	PKHTMR,f
	    
pkclr	    movf	PKHTMR,w
	    xorwf	HmSec,w		
	    btfss	status,z	;
	    return
	    movf	PkHOpt,w	;get peak hold time option
	    call	PHOtab
pkoff	    addwf	HmSec,w		;set PK timer
	    movwf	PKHTMR
manclr	    clrf	dotvl
	    clrf	dotvr
	    bcf		AuxInd,IND1	
	    bcf		AuxInd,IND2
	    return

PHOtab	    brw
	    retlw	0xff	;opt 0	off
	    retlw	.10	;opt 1 = 1s
	    retlw	.30	;opt 2 = 3s
	    retlw	.1	;peak hold

;save DC offset preload value	    
SetDCO:	    call	CentreDot    
	    
	    banksel	DCPldH
	    movf	DCRldH,w
	    movwf	DCPldH
	    movf	DCRldL,w
	    movwf	DCPldL
	    return
	    
DCOffset:   
	    banksel	Mode
	    movf	Mode,w 
	    xorlw	0x03
	    btfss	status,z
	    return    
	    ;if mode 3 - adjust output of latch pulse to null DC offset	    
	    movlw	.117	;test lower threshold
	    subwf	Phase,w
	    btfsc	status,c    
	    ;lower duty cycle to 0x0001 min
	    bra		DCOuppr
	    movlw	1
	    subwf	DCRldL,f
	    btfsc	status,c
	    return
	    decfsz	DCRldH,f ;
	    return
	    incf	DCRldH,f
	    
	    return
	    
DCOuppr	    movlw	.137		;test upper threshold
	    subwf	Phase,w
	    btfss	status,c    
	    return
	    movlw	1
	    addwf	DCRldL,f
	    btfss	status,c
	    return
	    
	    incfsz	DCRldH,f
	    return
	    comf	DCRldH,f ;inc to FF
	    comf	DCRldL,f
	    return


;----------------------------------------------------------------------------------


; remaining code goes here
	    
DoHmSC:	    ;do 100millisecond counter
	    decfsz	FrmCnt,f	;decrement fram count down to zero
	    return
	    movlw	.13		; 100mS / (400uS * 19)
	    movwf	FrmCnt
	    incf	HmSec,f
	    return
	    
;VFD display routines called from timer interrupt or main loop

setTimer: 	;usedto trigger adc go at regular intervals
	    banksel	TMR0
	    movlw	.255 - (.8*.17) 	;osc/4 17us 
	    movwf	TMR0	;set timer	
	    return	

;calculate bit for shifting to display 
;anode bits are determained by asigning a value to each anode from the bottom up 
;and comparing to display value	    
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
	    movlw	0x04		;increase this to dim ref
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

shft	    ;Call	Shftout		;shift output bytes to display
	    return


tstODD	    movf	FrmNo,w
	    andlw	0x01
	    btfsc	status,z
	    goto	evnFrm		;do even frame output

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

	    Banksel	SPBRGH	    ;BANK 3
	    clrf	SPBRGH
	    movlw	0x10	    ;use 4 for 16MHz
	    movwf	SPBRGL

	    ;Banksel	BAUDCON	    ;BANK 3
	    movlw	B'00011000'
	    movwf	BAUDCON
	    
	    ;Banksel	RCSTA	    ;BANK 3
	    bsf		RCSTA,SPEN	    
	    ;Banksel	TXSTA	    ;set tx control BANK 3
	    movlw	B'10110000'
	    movwf	TXSTA
	    return	   

	    
Shftout:   ;switch off PWM and enable UART o/p
	    movlb	0
	    
	    ;banksel	PWM3CON
	    ;bcf		PWM3CON,EN
	    ;clrf	PWM3TMRH
	    
	    movlw	PB29
	    movwf	FSR0L	    ;set indirection pointer
	    clrf	FSR0H
	    movlw	0x05	    ;set byte counter
	    movwf	intemp0
  
 
	    Banksel	TXREG	    ;BANK 3
waitTXF     moviw	INDF0++	    ;get byte at pointer and increment FSR
	    movwf	TXREG	    ;output to shifter

	    ;Banksel	TXSTA	    ;BANK 3
waitlst     btfss	TXSTA,TRMT	    
	    goto	waitlst	    ;wait for last buffer clear	    
	    decfsz	intemp0,f   ;decrement counter
	    goto	waitTXF	    ;loop 5 bytes out	    
    

	    ;banksel	PWM3CON
	    ;clrf	PWM3TMRL
	    ;bsf		PWM3CON,EN
	    ;bsf		PWM3LDCON,LDA
	    
	    ;Banksel	PortA	    ;BANK 0
	    movlb	0
	    
	    movf	DCRldH,w
	    movwf	DCtmr
DCDC	    bsf		disport,latch
	    nop
	    nop
	    decfsz	DCtmr,f
	    bra		DCDC
	    bcf		disport,latch  	  	
	    return
	    
;**********************************************************************************
;Flash  read and write 
	    
;Save PREFs    (will hang for 4mS so clear display first)
PrfSave:    call	FLClr		;erase a row (16 bytes)
	    call	FLWrite		;save 16 bytes @ PREFS as RETLW 0x??
	    movlb	0		;select bank 0
	    clrf	Mode		;reset mode
	    return
	    
	    
	    
	    
;---------------------------------------------------------------------------------	    
; This code block will read 1 word of program
; memory at the memory address:
;PROG_ADDR_HI : PROG_ADDR_LO
; data will be returned in the variables;
; PROG_DATA_HI, PROG_DATA_LO


	    
FLRead:
	    BANKSEL	PMADRL		; Select Bank for PMCON registers
	    MOVLW	0x80		;high endurance flash 0x780-0x7ff
	    MOVWF	PMADRL		; Store LSB of address
	    MOVLW	0x07 ;
	    MOVWF	PMADRH		; Store MSB of address
	    BCF		PMCON1,CFGS	; Do not select Configuration Space
	    BSF		PMCON1,RD	; Initiate read
	    NOP				; Ignored (Figure 10-2)
	    NOP				; Ignored (Figure 10-2)
	    MOVF	PMDATL,W	; Get LSB of word

	    MOVF	PMDATH,W	; Get MSB of word
	    return
	    
; This row erase routine assumes the HEF is located at 0x780:
;clear display before call because of 2mS hang
	    
FLCLR:	    BCF		INTCON,GIE  ; Disable ints so required sequences will execute properly
	    BANKSEL	PMADRL
	    MOVLW	0x80	    ; Load lower 8 bits of erase address boundary
	    MOVWF	PMADRL
	    MOVLW	0x07	    ; Load upper 6 bits of erase address boundary
	    MOVWF	PMADRH
	    BCF		PMCON1,CFGS ; Not configuration space
	    BSF		PMCON1,FREE ; Specify an erase operation
	    BSF		PMCON1,WREN ; Enable writes
	    MOVLW	55h	    ; Start of required sequence to initiate erase
	    MOVWF	PMCON2	    ; Write 55h
	    MOVLW	0AAh ;
	    MOVWF	PMCON2	    ; Write AAh
	    BSF		PMCON1,WR   ; Set WR bit to begin erase
	    NOP			    ; NOP instructions are forced as processor starts
	    NOP			    ; row erase of program memory.
				    ;
				    ; The processor stalls until the erase process is complete
				    ; after erase processor continues with 3rd instruction
	    BCF		PMCON1,WREN ; Disable writes
	    BSF		INTCON,GIE  ; Enable interrupts	    
	    return
	    
; This write routine assumes the following:
	    ;writes 16 bytes @ PREFS to HEF @ 0x780
	    ;as RETLW 0x?? 

FLWrite:    BCF		INTCON,GIE ; Disable ints so required sequences will execute properly
	    BANKSEL	PMADRH	    ; Bank 3
	    movlw	.16
	    movwf	Temp0	    ;set counter
	    movlw	0x07	    ;set address of HEF
	    MOVWF	PMADRH	    ;
	    movlw	0x80
	    MOVWF	PMADRL	    ;
	    
	    movlw	PREFS	    ;address of prefs into fsr
	    MOVWF	FSR0L	    ;
	    MOVLW	0x00	    ; Load initial data address
	    MOVWF	FSR0H ;
	    BCF		PMCON1,CFGS ; Not configuration space
	    BSF		PMCON1,WREN ; Enable writes
	    BSF		PMCON1,LWLO ; Only Load Write Latches
	    bra		LOOP+1
LOOP	    INCF	PMADRL,F    ; Still loading latches Increment address
	    MOVIW	FSR0++	    ; Load first data byte into lower
	    MOVWF	PMDATL	    ;
	    movlw	0x34	    ;RETLW instruction
	    MOVWF	PMDATH ;
	    MOVLW	55h	    ; Start of required write sequence:
	    MOVWF	PMCON2	    ; Write 55h
	    MOVLW	0AAh ;
	    MOVWF	PMCON2	    ; Write AAh
	    BSF		PMCON1,WR   ; Set WR bit to begin write
	    NOP			    ; NOP instructions are forced as processor
				    ; loads program memory write latches
	    NOP ;
	    decfsz	temp0,f
	    GOTO	LOOP		; Write next latches
START_WRITE
	    BCF		PMCON1,LWLO ; No more loading latches - Actually start Flash program
	    ; memory write
	    MOVLW	55h	    ; Start of required write sequence:
	    MOVWF	PMCON2	    ; Write 55h
	    MOVLW	0AAh ;
	    MOVWF	PMCON2	    ; Write AAh
	    BSF		PMCON1,WR   ; Set WR bit to begin write
	    NOP			    ; NOP instructions are forced as processor writes
				    ; all the program memory write latches simultaneously
	    NOP			    ; to program memory.
				    ; After NOPs, the processor
				    ; stalls until the self-write process in complete
				    ; after write processor continues with 3rd instruction
	    BCF		PMCON1,WREN ; Disable writes
	    BSF		INTCON,GIE  ; Enable interrupts
	    
	    return
    
	    ORG	    0x400	    ;align table with page boundary
	    
;VU scale +5 at top, -5 middle, -30 bottom	    
	    ;take 8bit adc value 0-fsd and converts to bar number
ScaleTab:   BRW	   
	    RETLW  .0
	    RETLW  .0
	    RETLW  .0
	    RETLW  .0
	    RETLW  .1
	    RETLW  .2
	    RETLW  .2
	    RETLW  .3
	    RETLW  .3
	    RETLW  .4
	    RETLW  .4
	    RETLW  .4
	    RETLW  .5
	    RETLW  .6
	    RETLW  .8
	    RETLW  .9
	    RETLW  .10
	    RETLW  .11
	    RETLW  .12
	    RETLW  .13
	    RETLW  .14
	    RETLW  .14
	    RETLW  .15
	    RETLW  .16
	    RETLW  .17
	    RETLW  .17
	    RETLW  .18
	    RETLW  .19
	    RETLW  .19
	    RETLW  .20
	    RETLW  .20
	    RETLW  .21
	    RETLW  .21
	    RETLW  .22
	    RETLW  .23
	    RETLW  .23
	    RETLW  .23
	    RETLW  .24
	    RETLW  .24
	    RETLW  .25
	    RETLW  .26
	    RETLW  .27
	    RETLW  .28
	    RETLW  .29
	    RETLW  .30
	    RETLW  .31
	    RETLW  .32
	    RETLW  .33
	    RETLW  .34
	    RETLW  .35
	    RETLW  .36
	    RETLW  .36
	    RETLW  .37
	    RETLW  .38
	    RETLW  .39
	    RETLW  .40
	    RETLW  .40
	    RETLW  .41
	    RETLW  .42
	    RETLW  .43
	    RETLW  .43
	    RETLW  .44
	    RETLW  .45
	    RETLW  .45
	    RETLW  .46
	    RETLW  .47
	    RETLW  .47
	    RETLW  .48
	    RETLW  .49
	    RETLW  .49
	    RETLW  .50
	    RETLW  .51
	    RETLW  .52
	    RETLW  .52
	    RETLW  .52
	    RETLW  .53
	    RETLW  .53
	    RETLW  .54
	    RETLW  .55
	    RETLW  .55
	    RETLW  .56
	    RETLW  .56
	    RETLW  .57
	    RETLW  .57
	    RETLW  .58
	    RETLW  .58
	    RETLW  .59
	    RETLW  .59
	    RETLW  .60
	    RETLW  .60
	    RETLW  .61
	    RETLW  .61
	    RETLW  .62
	    RETLW  .62
	    RETLW  .63
	    RETLW  .63
	    RETLW  .63
	    RETLW  .64
	    RETLW  .64
	    RETLW  .65
	    RETLW  .65
	    RETLW  .66
	    RETLW  .66
	    RETLW  .67
	    RETLW  .67
	    RETLW  .68
	    RETLW  .68
	    RETLW  .68
	    RETLW  .69
	    RETLW  .69
	    RETLW  .69
	    RETLW  .70
	    RETLW  .70
	    RETLW  .70
	    RETLW  .71
	    RETLW  .71
	    RETLW  .72
	    RETLW  .72
	    RETLW  .72
	    RETLW  .73
	    RETLW  .73
	    RETLW  .73
	    RETLW  .74
	    RETLW  .74
	    RETLW  .75
	    RETLW  .75
	    RETLW  .75
	    RETLW  .76
	    RETLW  .76
	    RETLW  .76
	    RETLW  .77
	    RETLW  .77
	    RETLW  .77
	    RETLW  .78
	    RETLW  .78
	    RETLW  .78
	    RETLW  .78
	    RETLW  .79
	    RETLW  .79
	    RETLW  .79
	    RETLW  .80
	    RETLW  .80
	    RETLW  .80
	    RETLW  .81
	    RETLW  .81
	    RETLW  .81
	    RETLW  .82
	    RETLW  .82
	    RETLW  .82
	    RETLW  .82
	    RETLW  .83
	    RETLW  .83
	    RETLW  .83
	    RETLW  .84
	    RETLW  .84
	    RETLW  .85
	    RETLW  .85
	    RETLW  .85
	    RETLW  .85
	    RETLW  .85
	    RETLW  .85
	    RETLW  .86
	    RETLW  .86
	    RETLW  .86
	    RETLW  .87
	    RETLW  .87
	    RETLW  .87
	    RETLW  .88
	    RETLW  .88
	    RETLW  .88
	    RETLW  .88
	    RETLW  .88
	    RETLW  .89
	    RETLW  .89
	    RETLW  .89
	    RETLW  .89
	    RETLW  .89
	    RETLW  .89
	    RETLW  .90
	    RETLW  .90
	    RETLW  .91
	    RETLW  .91
	    RETLW  .91
	    RETLW  .91
	    RETLW  .92
	    RETLW  .92
	    RETLW  .92
	    RETLW  .92
	    RETLW  .92
	    RETLW  .93
	    RETLW  .93
	    RETLW  .93
	    RETLW  .93
	    RETLW  .94
	    RETLW  .94
	    RETLW  .94
	    RETLW  .94
	    RETLW  .94
	    RETLW  .95
	    RETLW  .95
	    RETLW  .95
	    RETLW  .95
	    RETLW  .96
	    RETLW  .96
	    RETLW  .96
	    RETLW  .96
	    RETLW  .97
	    RETLW  .97
	    RETLW  .97
	    RETLW  .97
	    RETLW  .97
	    RETLW  .98
	    RETLW  .98
	    RETLW  .98
	    RETLW  .98
	    RETLW  .99
	    RETLW  .99
	    RETLW  .99
	    RETLW  .99
	    RETLW  .100
	    RETLW  .100
	    RETLW  .100
	    RETLW  .100
	    RETLW  .100
FSD	    EQU		.223 ;fsd level 
	    
	    org	    0x780	;high endurance flash
FPRTab	    RETLW   0x02	;PREF table store in HEF
	    RETLW   0x02
	    RETLW   .75
	    RETLW   0x14	;DCPldL offset value
	    RETLW   0xA9	;DCPldH
	    RETLW   0x00	;DCOmode bits 
	    RETLW   0x00	    
	    RETLW   0x00
	    RETLW   0x00	    
	    RETLW   0x00	    
	    RETLW   0x00	    
	    RETLW   0x00
	    RETLW   0x00	    
	    RETLW   0x00	
	    RETLW   0x00	    
	    RETLW   0x00	    
	    END                       ; directive 'end of program'


