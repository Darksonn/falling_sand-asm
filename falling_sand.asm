BITS 16
  mov ax, 7C0h
  mov ds, ax

  push ds ; register keyboard handler
  push word 0
  pop ds
  cli
  mov [9h * 4], word keyboardhandler
  mov [9h * 4 + 2], word 7C0h
  sti
  pop ds

%define RANDOM 993
%define SPAWNING_TYPE 994
%define IS_SPAWNING 995
%define CLOCK_STEP 996
%define POSITION 997
%define IS_STEPPING_FLAG 999
%define STATE 1000

; how many clock pulses from the 100 Hz clock should happen for each game
; step?
%define CLOCK_STEPS_PER_STEP 4
%define WIN_W 80
%define WIN_H 24
%define WIN_SIZE (WIN_W*WIN_H)

  mov byte [CLOCK_STEP], 0
  mov byte [IS_SPAWNING], 0

  ; hidden cursor
  mov cx, 2607h
  mov ah, 01h
  int 10h

  call setup

step_start:
  call gen_random

  call print_state
  cmp byte [IS_SPAWNING], 1
  jne .nospawn
  mov bx, [POSITION]
  mov al, [SPAWNING_TYPE]
  mov [STATE+bx], al

.nospawn:
  mov al, [IS_STEPPING_FLAG]
  cmp al, 0
  jne .do_step
  jmp next_step_start
.do_step:
  mov al, [CLOCK_STEP]
  cmp al, CLOCK_STEPS_PER_STEP
  je really_do_step
  inc al
  mov [CLOCK_STEP], al
next_step_start:
  hlt ; wait for next interrupt (timer)
  jmp step_start

really_do_step:
  mov byte [CLOCK_STEP], 0
  mov bx, WIN_SIZE
.step:
  dec bx
  mov al, [STATE+bx]
  cmp al, 1
  jle .next ; if the current item is wall or air, do nothing
; take a look at what's below (we init memory with wall below the lowest column)
  mov ah, [STATE+WIN_W+bx]
  cmp ah, 0
  je .fall ; air is below, so we fall
  ; no air below, move randomly right or left

  mov cl, [STATE+bx]
  cmp cl, 3
  je .check_below
.move_ok:
  push cx
  push bx
  call gen_random
  and bl, 3


  pop dx
  mov bh, 0
  add bx, dx
  sub bx, 2
  mov ax, [STATE+bx]
  cmp ax, 0
  pop cx
  jne .nope ; we can't move over here
  mov [STATE+bx], cl
  mov bx, dx
  mov byte [STATE+bx], 0

.nope:
  mov bx, dx
  jmp .next

.check_below:
  cmp byte [STATE+WIN_W+bx], 2
  je .fall_water
  cmp byte [STATE+WIN_W-1+bx], 0
  je .move_ok
  cmp byte [STATE+WIN_W+bx], 0
  je .move_ok
  cmp byte [STATE+WIN_W+1+bx], 0
  je .move_ok
  jmp .next

.fall_water:
  mov [STATE+WIN_W+bx], al
  mov byte [STATE+bx], 2
  jmp .next
.fall:
  mov [STATE+WIN_W+bx], al
  mov byte [STATE+bx], 0

.next:
  cmp bx, 0
  jne .step
  jmp next_step_start

gen_random:
  mov al, [RANDOM]
  shr al, 1
  mov bl, 73
  mul bl
  add al, 7
  mov [RANDOM], al
  mov bl, al
  ret

setup:
  mov bx, 0
.clear_loop:
  mov byte [STATE+bx], 0
  inc bx
  cmp bx, WIN_W * (WIN_H - 1)
  jne .clear_loop
.clear_loop_2:
  mov byte [STATE+bx], 1
  inc bx
  cmp bx, WIN_SIZE + WIN_W
  jne .clear_loop_2
  mov bx, 0
.clear_loop_3:
  mov byte [STATE+bx], 1
  mov byte [(STATE+WIN_W-1)+bx], 1
  add bx, WIN_W
  cmp bx, WIN_SIZE + WIN_W
  jne .clear_loop_3

  ; set up timer
  ; the timer interrupts the hardware with 100 Hz
  mov al, 36h
  out 43h, al
  mov ax, 11931 ; 100 Hz
  out 40h, al
  mov ah, al
  out 40h, al
  ret

print_state:
  ; move cursor to upper left
  mov ah, 02h
  mov bh, 0
  mov dh, 0
  mov dl, 0
  int 10h

  mov bx, 0 ; character counter
.print_char:
  push bx
  cmp bx, [POSITION]
  jne .no_cursor
  mov al, 'x'
  jmp .print_now

.no_cursor:
  ; read state
  mov bl, [STATE+bx]
  mov bh, 0
  mov al, [state_char+bx]

.print_now:
  ; print character
  mov ah, 0eh
  mov bh, 0
  mov bl, 0
  int 10h
  pop bx

  inc bx
  cmp bx, WIN_SIZE
  jne .print_char
  ret



;print:
;  pusha
;  mov ah, 0Eh
;  xor bh, bh
;  cld
;.repeat:
;  lodsb
;  cmp al, 0
;  je .end
;  int 10h
;  jmp .repeat
;.end:
;  popa
;  ret

keyboardhandler:
  pusha

  in al, 60h

  test al, 80h
  jnz .released

.pressed:
  mov cl, 1
  cmp al, 1fh ; 0x1f is S
  je .swap_step
  cmp al, 48h
  je .arrow_key_up
  cmp al, 50h
  je .arrow_key_down
  cmp al, 4bh
  je .arrow_key_left
  cmp al, 4dh
  je .arrow_key_right
  cmp al, 02h
  jge .spawn

  jmp .end
.arrow_key_up:
  mov ax, [POSITION]
  add ax, -WIN_W
  cmp ax, 0
  jl .end
  mov [POSITION], ax
  jmp .end
.arrow_key_down:
  mov ax, [POSITION]
  add ax, WIN_W
  cmp ax, WIN_SIZE
  jge .end
  mov [POSITION], ax
  jmp .end
.arrow_key_left:
  add word [POSITION], -1
  jmp .end
.arrow_key_right:
  add word [POSITION], 1
  jmp .end
.spawn:
  cmp al, 05h
  jg .end
  sub al, 02h
  mov [SPAWNING_TYPE], al
  mov byte [IS_SPAWNING], cl
  jmp .end

.swap_step:
  xor byte [IS_STEPPING_FLAG], 1
  jmp .end
.released:
  mov cl, 0
  xor al, 80h
  cmp al, 02h
  jge .spawn

.end:
  mov al, 20h
  out 20h, al
  popa
  iret

  state_char db ' #~.'
  times 510 - ($-$$) db 0
  dw 0AA55h

