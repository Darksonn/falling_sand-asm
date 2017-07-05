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

; it's a deliberate choice that IS_STEPPING_FLAG is just below STATE, since that
; means if something at [STATE+0] is trying to move to the left, then it will
; meet IS_STEPPING_FLAG, but since it is trying to move to the left, we are
; currently stepping, which means IS_STEPPING_FLAG is 1, which is the same as
; wall


; how many clock pulses from the 100 Hz clock should happen for each game step?
%define CLOCK_STEPS_PER_STEP 2
%define WIN_W 80
%define WIN_H 24
%define WIN_SIZE (WIN_W*WIN_H)

  mov byte [CLOCK_STEP], 0
  mov byte [IS_SPAWNING], 0

  ; make the cursor hidden
  mov cx, 2607h
  mov ah, 01h
  int 10h

setup:
  mov bx, 0
.clear_loop: ; make the entire map air
  mov byte [STATE+bx], 0
  inc bx
  cmp bx, WIN_W * (WIN_H - 1)
  jne .clear_loop
  ; make the two lowest rows wall
  ; note that the lowest row is outside the view
  ; the row outside the view is just to make sure that water/sand can't fall out
  ; of the buffer
.clear_loop_2:
  mov byte [STATE+bx], 1
  inc bx
  cmp bx, WIN_SIZE + WIN_W
  jne .clear_loop_2
  mov bx, 0
  ; add walls
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

step_start:
  ; this makes it harder for the primitive random number generator to enter a
  ; short period
  add byte [RANDOM], 1

  ; update the screen
  call print_state
  ; if we are spawning, draw it on the screen
  cmp byte [IS_SPAWNING], 1
  jne .nospawn
  mov bx, [POSITION]
  mov al, [SPAWNING_TYPE]
  mov [STATE+bx], al

.nospawn:
  ; check if we are currently running the simulation
  cmp byte [IS_STEPPING_FLAG], 0
  jne .do_step
  jmp next_step_start
.do_step:
  ; yep, the game is running
  ; let's check if it's time to do a game tick
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
  ; we perform the .step part for every position
  ; note that we do it in reverse order, since otherwise stuff we just moved
  ; down will again be moved down when we reach it next time
  ; this works since nothing ever moves up
  mov bx, WIN_SIZE
.step:
  dec bx
  mov cl, [STATE+bx]
  cmp cl, 1
  ; if the current item is wall or air, do nothing
  ; we store in cl, since it is used later in several places
  jle .next
  ; take a look at what's below
  ; remember that below the visible world is a row of wall
  cmp byte [STATE+WIN_W+bx], 0
  ; the following jump jumps if there is air below
  je .fall
  ; no air below, move randomly right or left

  ; cl currently contains the current item
  ; check if the current item is sand, in which case we need to check the three
  ; blocks below in order to make it form a pile
  cmp cl, 3
  je .check_below
.move_ok:
  ; either we are not sand, or the blocks below the sand say it's okay to move
  ; randomly either right or left
  push cx
  mov dx, bx ; bx contains the stepping index, but we need the register bx

  ; this code generates a random byte using a very bad random number generator
  ; we have to use al to store the value, since mul requires it there
  mov al, [RANDOM]
  shr al, 1
  mov bl, 73
  mul bl
  add al, 57
  mov [RANDOM], al
  mov bl, al

  ; get the two lowest bits in the random number
  and bl, 3
  ; the random number is used to find the change in bx where we should move the
  ; item to

  ; since bl has four values, but moving left, right or staying still has 3
  ; we must map one of them to another
  cmp bl, 0
  jne .not_zero
  mov bl, 2
.not_zero:
  ; make bx = bl
  xor bh, bh
  ; add the index of the current piece of sand to the change in index
  add bx, dx
  ; make it so not all movement is to the right
  ; note that bx != 0 here
  sub bx, 2
  ; check if we are trying to move into something that is not air
  cmp byte [STATE+bx], 0
  pop cx
  jne .nope ; we can't move over here
  ; perform the actual move
  mov [STATE+bx], cl
  ; the commands below do not reset bx to the current index, but rather we
  ; continue stepping from where we moved to
  ; this fixes a bug when items move left and are then stepped twice
  ; this causes no problems when moving to the right, since even though we touch
  ; the current index again, it will be air and therefore skipped
  mov cx, bx
  mov bx, dx
  ; we do still have to move the original index back to bx, since only bx can be
  ; used to index buffers
  mov byte [STATE+bx], 0
  mov dx, cx

.nope:
  mov bx, dx
  jmp .next

.check_below:
  ; this code runs when the item is sand and we need to check what's below
  ; this code causes sand to fall through water and to make a stable pile when
  ; on wall
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
  ; when .fall_water is jumped to, cl contains the current item type
  mov [STATE+WIN_W+bx], cl
  mov byte [STATE+bx], 2
  jmp .next
.fall:
  ; when .fall is jumped to, cl contains the current item type
  mov [STATE+WIN_W+bx], cl
  mov byte [STATE+bx], 0

.next:
  ; check if the game step is done
  cmp bx, 0
  ; if not, do the next step
  jne .step
  ; otherwise go back to the outer loop
  jmp next_step_start

print_state:
  ; this function draws the screen
  ; move cursor to upper left
  mov ah, 02h
  mov bh, 0
  mov dh, 0
  mov dl, 0
  int 10h

  mov bx, 0 ; character counter
.print_char:
  ; check if we are at the cursor
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

  ; next iteration
  inc bx
  cmp bx, WIN_SIZE
  jne .print_char
  ret

; the function below can be used to print a zero-terminated string saved in
; the register `si`

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

; the function below is called when a keyboard interrupt arrives
keyboardhandler:
  pusha

  in al, 60h

  test al, 80h
  jnz .released

.pressed:
  ; figure out what key it was
  ; cl is used in .spawn, and is 0 if the key was released
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
  ; we check whether we can move cursor up, and if so, do it
  mov ax, [POSITION]
  add ax, -WIN_W
  cmp ax, 0
  jl .end
  mov [POSITION], ax
  jmp .end
.arrow_key_down:
  ; we check whether we can move cursor down, and if so, do it
  mov ax, [POSITION]
  add ax, WIN_W
  cmp ax, WIN_SIZE
  jge .end
  mov [POSITION], ax
  jmp .end
.arrow_key_left:
  ; we check whether we can move cursor left, and if so, do it
  mov ax, [POSITION]
  cmp ax, 0
  je .end
  add word [POSITION], -1
  jmp .end
.arrow_key_right:
  ; we check whether we can move cursor right, and if so, do it
  mov ax, [POSITION]
  cmp ax, WIN_SIZE - 1
  je .end
  add word [POSITION], 1
  jmp .end
.spawn:
  ; set the spawning flag to the appropriate value
  cmp al, 05h
  jg .end
  ; al is the key code, the number keys start at 02h, so we change the interval
  ; to fit the desired values
  sub al, 02h
  mov [SPAWNING_TYPE], al
  mov byte [IS_SPAWNING], cl ; cl corresponds to the press/release status
  jmp .end

.swap_step:
  ; we change whether or not we are stepping
  xor byte [IS_STEPPING_FLAG], 1
  jmp .end
.released:
  ; cl is used by .spawn
  mov cl, 0
  xor al, 80h
  cmp al, 02h
  jge .spawn

.end:
  mov al, 20h
  out 20h, al
  popa
  iret

  ; a char array describing how the items look
  state_char db ' #~.'
  ; the file must be exactly 512 bytes, so we pad it with zeroes
  times 510 - ($-$$) db 0
  dw 0AA55h

