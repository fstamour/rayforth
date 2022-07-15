;; this is a forth written in assembly... or at least it tries to be

bits 64

;; Constants
        CELLSIZE equ 8
        STACKSIZE equ 64

;; static data stuff
SECTION .data
align 8
        helloStr db "RayForth v0", 10
        helloLen equ $ -helloStr

        keytestStr db "Press a key and it will be printed back", 10
        keytestStrLen equ $ -keytestStr

        program db "65 emit 10 emit", 10
        programLen equ $ -program


;; here's where these things go, apparently
SECTION .bss
align 8

;; Parameter stack
        DATASTACK resb CELLSIZE*64
        DATASTACKBOTTOM equ $ - CELLSIZE

;; Parameter Stack Macros
%macro DPUSH 1
        sub rbp, CELLSIZE
        mov qword [rbp], qword %1
%endmacro

%macro DPOP 1
        mov qword %1, qword [rbp]
        add rbp, CELLSIZE
%endmacro


;; Other memory zones
PADDATA:
        resb 4096
TIBDATA:
        resb 4096

;; dictionary here?
;; colon and code definitions have the same structure
;; LINK   FLAGS|COUNT   NAME   code here...

;; inspired by Itsy Forth
%define link 0
%define IMMEDIATE 0x80

%macro head 3
%{2}_entry:
        %%link dq link
%define link %%link
%strlen %%count %1
        db %3 + %%count,%1
%endmacro

%macro .colon 2-3 0
        head %1,%2,%3
%{2}:
%endmacro

%macro .constant 3
        head %1,%2,0
        val_ %+ %2 dq %3
%{2}:
        mov r8, val_ %+ %2
        mov r9, [r8]
        DPUSH r9
        ret
%endmacro

%macro .variable 3
        head %1,%2,0
        val_ %+ %2 dq %3
%{2}:
        DPUSH val_ %+ %2
        ret
%endmacro


SECTION mysection,EWR
DICTIONARY:
;; primitives
.colon "@",fetch
        DPOP r8
        mov qword r9, qword [r8]
        DPUSH r9
        ret

.colon "!",store
        DPOP r8
        DPOP r9
        mov qword [r8], qword r9
        ret

.colon "SP@", spFetch
        mov r8, rbp
        DPUSH r8
        ret

.colon "RP@", rpFetch
        mov r8, rsp
        DPUSH r8
        ret

.colon "0=", zeroEqual
        DPOP r8
        test r8, r8
        pushf
        pop r8
        shr r8, 6+8
        and r8, 1
        mov r9, 0
        sub r9, r8
        DPUSH r9
        ret

.colon "+", plus
        DPOP r8
        DPOP r9
        add r8, r9
        DPUSH r8
        ret

.colon "NAND", nand
        DPOP r8
        DPOP r9
        and r8, r9
        not r8
        DPUSH r8
        ret

.colon "EXIT", exit
        pop r8
        pop r9
        push r8
        ret

;; ideally we should set the terminal to raw or something first
.colon "KEY", key
        sub rbp, 4
        mov rax, 3
        mov rbx, 1
        mov rcx, rbp
        mov rdx, 1
        int 0x80
        ret

.colon "EMIT", emit
        mov r8, rbp
        DPUSH r8
        DPUSH 1
        call type
        add rbp, CELLSIZE
        ret

;; end of SectorForth primitives, start of mine

;; TYPE
.colon "TYPE", type
        mov rax, 4
        mov rbx, 1
        DPOP rdx
        DPOP rcx
        int 0x80
        ret

.colon "SQUARE", square
        call dup
        call multiply
        ret

.colon "DUP", dup
        mov r8, [rbp]
        DPUSH r8
        ret

.colon "SWAP", swap
        DPOP r8
        DPOP r9
        DPUSH r8
        DPUSH r9
        ret

.colon "DROP", drop
        add rbp, CELLSIZE
        ret

.colon "OVER", over
        mov r8, [ebp+CELLSIZE]
        DPUSH r8
        ret

.colon "*", multiply
        DPOP r8
        DPOP r9
        imul r8, r9
        DPUSH r8
        ret

.colon "CR", cr
        DPUSH 10
        call emit
        ret

.colon "C@", cfetch
        DPOP r8
        xor rbx, rbx
        mov bl, [r8]            ; hmmm... we do want to read a single char here
        DPUSH rbx
        ret

.colon "C!", cstore
        DPOP r8
        DPOP rbx                ; same here
        mov [r8], bl
        ret

.colon "BYE", bye
        mov rax, 1
        mov rbx, 0
        int 0x80

.variable "STATE", state, 76
.variable "HERE", here, 77
.variable "LATEST", latest, 78
.variable "TIB", TIB, TIBDATA
.variable ">IN", TIBIN, 0

;; the program code here
SECTION .text
align 8

global _start

;; perform various initialization stuff
init:
        mov rdi, PADDATA
        mov rcx, 4096
        mov al, ' '
        rep stosb

        mov rdi, TIBDATA
        mov rcx, 4096
        mov al, ' '
        rep stosb

        mov rdi, DATASTACK
        mov rcx, CELLSIZE*STACKSIZE
        mov al, 0
        rep stosb

        mov rbp, DATASTACKBOTTOM
        ret


;; --- more code ---
;; function things
display:
        DPUSH PADDATA
        DPUSH 4096
        call type
        call cr
        ret

hello:
        DPUSH helloStr
        DPUSH helloLen
        call type
        ret

;; Inner interpreter stuff
;; do we even have one? :-/
;; answer is nope, with the magic of STC

;; Outer interpreter stuff

;;;; THIS IS THE ENTRY POINT
_start:
        call init
        call hello
        call testword
        call display

;;;; THIS IS THE EXIT POINT
coda:
        mov rax, 1
        mov rbx, 0
        int 0x80

testexitinner:
        DPUSH 'A'
        call emit
        call exit               ; exits from outer
        ret

testexitouter:
        call testexitinner
        DPUSH 'B'
        call emit
        ret

testword:
        ; test stack and emit, emit EDC
        DPUSH 'C'
        DPUSH 'D'
        DPUSH 'E'
        call emit
        call emit
        call emit
        call cr

        ; test fetch and store, copy 8 bytes of hello string (offset 4)
        ; to the pad ("orth V0", 10)
        DPUSH helloStr+4
        call fetch
        DPUSH PADDATA
        call store

        ; test 0=, emit 0 and 1
        DPUSH 0
        call zeroEqual
        DPOP rax
        add rax, '1'
        DPUSH rax
        call emit

        DPUSH 1
        call zeroEqual
        DPOP rax
        add rax, '1'
        DPUSH rax
        call emit

        ; test +, emit A
        DPUSH 60
        DPUSH 5
        call plus
        call emit

        ; test NAND, emit O
        DPUSH 0xffffffffffffffff
        DPUSH 0xffffffffffffffb0
        call nand
        call emit

        ; test exit, emit A but not B
        call testexitouter

        ; test for KEY
        DPUSH keytestStr
        DPUSH keytestStrLen
        call type
        call key
        call emit

        ; test SQUARE colon definition (but not the whole entry)
        ; also tests * and DUP code definitions
        ; emit C
        DPUSH 8
        call square
        DPUSH 3
        call plus
        call emit

        ; test HERE as a variable, emit E
        call here
        call fetch              ; save the value of here on the stack

        DPUSH '*'
        call emit

        DPUSH 69
        call here
        call store
        call here
        call fetch
        call emit

        call here
        call store              ; and restore the value of here
        call cr

        ; test dictionary structure
        DPUSH here_entry
        DPUSH CELLSIZE
        call plus
        call cfetch
        DPUSH '0'
        call plus
        call emit

        DPUSH ' '
        call emit

        DPUSH here_entry
        DPUSH CELLSIZE
        call plus
        DPUSH 1
        call plus
        DPUSH 4
        call type
        call cr

        ; more test for dictionary structure
        ; print the name of the word preceeding HERE
        DPUSH here_entry
        call fetch              ; address of the linked entry

        DPUSH CELLSIZE
        call plus               ; address of the count

        call dup
        call cfetch             ; get the count and move it out of the way
        call swap

        DPUSH 1                 ; increment the address
        call plus

        call swap

        call type               ; print the name
        call cr


        ; test C@, emit F from Forth
        DPUSH helloStr
        DPUSH 3
        call plus
        call cfetch
        call emit

        ; test C!, emit X and modifies PADDATA too
        DPUSH 88
        DPUSH PADDATA
        call cstore
        DPUSH PADDATA
        call cfetch
        call emit

        ; end of tests
        call cr
        ret
