; xor_fill_avx2.asm
; void fill_xor_bgra_avx2(uint32_t* dst, int width, int height, uint32_t t);
; Windows x64 ABI:
;   RCX = dst
;   EDX = width
;   R8D = height
;   R9D = t
;
; Pixel format: BGRA8888 (little-endian DWORD: 0xAARRGGBB)
; Output pattern:
;   v = (((x + t) & 255) XOR ((y + t) & 255))
;   R = v
;   G = (v<<1)&255
;   B = (v<<2)&255
;   A = 255

option casemap:none
option prologue:none
option epilogue:none

PUBLIC fill_xor_bgra_avx2

.data
;align 32
laneI   dd 0,1,2,3,4,5,6,7
mask255 dd 255
alphaFF dd 0FF000000h

.code
fill_xor_bgra_avx2 PROC
    ; rcx=dst, edx=width, r8d=height, r9d=t

    ; Move args to stable registers
    mov rbx, rcx        ; dst base
    mov r12d, edx       ; width
    mov r13d, r8d       ; height
    mov r14d, r9d       ; t

    test r12d, r12d
    jle  L_done
    test r13d, r13d
    jle  L_done

    ; Load constants
    vmovdqa ymm9, YMMWORD PTR [laneI]        ; lanes 0..7
    vpbroadcastd ymm10, DWORD PTR [mask255]  ; 255
    vpbroadcastd ymm11, DWORD PTR [alphaFF]  ; 0xFF000000
    movd xmm0, r14d
    vpbroadcastd ymm12, xmm0                ; t broadcast

    xor r15d, r15d                          ; y = 0

L_yloop:
    cmp r15d, r13d
    jge L_finish

    ; base = (y + t) & 255 (broadcast)
    mov eax, r15d
    add eax, r14d
    and eax, 255
    movd xmm1, eax
    vpbroadcastd ymm13, xmm1                ; base broadcast

    ; row pointer = dst + y*width
    mov eax, r15d
    imul eax, r12d
    lea rdi, [rbx + rax*4]                  ; rdi = row

    xor esi, esi                            ; x = 0

    ; blocks = width / 8
    mov ecx, r12d
    shr ecx, 3
    jz  L_xtail

L_xloop:
    ; xvec = x + lane
    movd xmm2, esi
    vpbroadcastd ymm0, xmm2
    vpaddd ymm0, ymm0, ymm9                 ; x+lane

    ; v = ((x+lane+t)&255) XOR base
    vpaddd ymm0, ymm0, ymm12
    vpand  ymm0, ymm0, ymm10
    vpxor  ymm0, ymm0, ymm13                ; v in 0..255

    ; Build BGRA dwords
    ; G = (v<<1)&255, B=(v<<2)&255, R=v
    vpslld ymm1, ymm0, 1
    vpand  ymm1, ymm1, ymm10
    vpslld ymm2, ymm0, 2
    vpand  ymm2, ymm2, ymm10

    vpslld ymm1, ymm1, 8                    ; G<<8
    vpslld ymm0, ymm0, 16                   ; R<<16

    vpor   ymm2, ymm2, ymm1
    vpor   ymm2, ymm2, ymm0
    vpor   ymm2, ymm2, ymm11

    vmovdqu YMMWORD PTR [rdi], ymm2

    add rdi, 32                             ; 8 pixels
    add esi, 8
    dec ecx
    jnz L_xloop

L_xtail:
    ; remainder = width & 7
    mov ecx, r12d
    and ecx, 7
    jz  L_nextrow

L_tail_loop:
    ; v = (((x + t) & 255) XOR base)
    mov eax, esi
    add eax, r14d
    and eax, 255
    ; recompute base scalar (base = (y+t)&255):
    mov edx, r15d
    add edx, r14d
    and edx, 255
    xor eax, edx                            ; eax = v (0..255)

    ; B=(v<<2)&255, G=(v<<1)&255, R=v
    mov r8d, eax                            ; v
    mov r9d, eax
    shl r9d, 1
    and r9d, 255                            ; G
    mov r10d, eax
    shl r10d, 2
    and r10d, 255                           ; B

    shl r8d, 16                             ; R<<16
    shl r9d, 8                              ; G<<8
    or  r10d, r9d
    or  r10d, r8d
    or  r10d, 0FF000000h

    mov DWORD PTR [rdi], r10d
    add rdi, 4
    inc esi
    dec ecx
    jnz L_tail_loop

L_nextrow:
    inc r15d
    jmp L_yloop

L_finish:
    vzeroupper

L_done:
    ret
fill_xor_bgra_avx2 ENDP

END
