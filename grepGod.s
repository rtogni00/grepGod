.intel_syntax noprefix       # Use Intel syntax for clarity
.global main              

.section .text
         .extern printf

# _start:
#     call main

main:
    push rbp

    lea rdi, [filePrompt]
    call printf
    lea rsi, [inputFile]
    
    call getUserInput

    lea rdi, [patternPrompt]
    call printf
    lea rsi, [pattern]
    call getUserInput

    #lea rdi, [filename]       # Load address of filename into rdi 
    lea rdi, [inputFile]
    call openFile

    mov [fileDescriptor], rax

    call allocateMem          # rax contains pointer to allocated mem

    mov rsi, rax              # rsi contains pointer to mem buffer
    mov [bufferPtr], rsi

    mov r8, [occurrences]     # initially set to 0

read_loop:  

    call readChunk            # rax contains file offset! The actual length of
                              # the line is stored in memory!

    mov rax, [lineLength]
    test rax, rax
    je end_read_loop

    #################################
    #push rdi
    #push rsi

    #lea rdi, [bytesRead]
    #mov rsi, [lineLength]
    #call printf
    
    #pop rsi
    #pop rdi
    #################################

    # rdi pointer to pattern
    # rsi pointer to buffer

    lea rdi, [pattern] 
    mov rsi, [bufferPtr]

    call searchPattern     # rax contains number of matches
    mov r8, [occurrences]
    add r8, rax
    mov [occurrences], r8
    jmp read_loop
    
end_read_loop:   
    lea rdi, [matches]
    mov rsi, [occurrences]
    call printf

    # end of program
    call endOfProgram
    
getUserInput:
    # rsi pointer to inputFile/pattern
    push rbp
    mov rbp, rsp
    sub rsp, 8            # Align stack

    push rsi
    push rdi
    push r8

    # Read filename/pattern into memory pointed by rsi
    xor rdi, rdi
    mov rdx, 64
    mov rax, 0
    syscall

    mov rdi, rsi
    
remove_newline:
    cmp byte ptr [rdi], 10    # Check if character is '\n'
    je replace_null
    cmp byte ptr [rdi], 0     # Stop if already null-terminated
    je done
    inc rdi               # Move to next character
    jmp remove_newline

replace_null:
    mov r8, 0
    mov [rdi], r8     # Replace '\n' with '\0'

done:
    pop r8
    pop rdi
    pop rsi
    add rsp, 8
    pop rbp
    ret 

openFile:
    push rbp
    mov rax, 2               # sys_open
    mov rsi, 2               # Flags (O_RDWR)
    mov rdx, 0               # Mode (not used)
    syscall
    pop rbp
    ret

readChunk:
    # rdi contains file descriptor (from openFile)
    # rsi contains pointer to mem buffer (from allocateMem)
    push rbp
    push rdx
    push rdi
    push rsi
    push rcx

read_more:  
    mov rdi, [fileDescriptor]
    mov rdx, [buffer_size]    # read buffer_size bytes
    mov rsi, [bufferPtr]
    mov rax, 0                # sys_read
    syscall                   # rax contains number of bytes read, NOT the
                              # actual line length

    test rax, rax             # bitwise end to check for EOF
    jz end_of_line

    js read_error             # jump if sign flag (rax is < 0)

    # check for newline in buffer
    mov r8, rsi               # to preserve rsi for resizeMem
    mov rcx, rax              # set rcx to # bytes read
    xor r9, r9                # set to 0 to use to compute #bytes before \n

find_newline:
    cmp byte ptr [r8], 10             # see if last character is newline
    je done_reading_line
    inc r8
    inc r9
    loop find_newline         # automatically decreases rcx, stops at 0

    # if newline not found, then line was longer than buffer -> double
    # but first restore file offset to what it was before reading
    call restoreFileOffset

    #mov [fileOffset], rax     # probably unnecessary

    call resizeMem
    mov [bufferPtr], rax       # pointer to new mem buffer
    jmp read_more

done_reading_line:
    # newline found, so set file offset to number
    # bytes before newline+1
    mov r10, [fileOffset]      # Super important! We want to set the offset
                               # to whatever it was after the previous read
                               # + the length of the line we just read!!
    inc r9
    mov [lineLength], r9       # Store the actual line length!!
    add r9, r10                # New fileOffset
    mov rdi, [fileDescriptor]  # Actually not necessary

    push rsi
    mov rsi, r9
    mov rdx, 0            # On next read, restart from offset

    mov rax, 8
    syscall

    mov [fileOffset], rax
    pop rsi
    
    pop rcx
    pop rsi
    pop rdi
    pop rdx
    pop rbp
    ret                      # rax contains the file offset

end_of_line:
    # If EOF, then set lineLength to 0
    push r11
    mov r11, 0
    mov [lineLength], r11
    pop r11
    pop rcx
    pop rsi
    pop rdi
    pop rdx
    pop rbp
    ret

read_error:
    push rdi
    mov rdi, [readError]
    call printf
    pop rdi

    pop rcx
    pop rsi
    pop rdi
    pop rdx
    pop rbp
    ret


allocateMem:
    push rbp
    push rdi
    push rsi
    push r10
    push r8
    push r9

    mov rdi, 0                # let OS choose memory address
    mov rsi, [buffer_size]    # allocate [buffer_size] bytes
    mov rdx, 0x22             # read & write permission
    mov r10, 0x22
    mov r8, -1
    mov r9, 0
    mov rax, 9                # syscall 9 (mmap)
    syscall

    # check for mmap failure
    #cmp rax, -1
    #je mmap_failed

    pop r9
    pop r8
    pop r10
    pop rsi
    pop rdi
    pop rbp
    ret

mmap_failed:
    # TODO check
    lea rdi, [memAllErr]
    call printf
    ret

restoreFileOffset:
    push rbp
    push rdi
    push rsi
    
    mov rdi, [fileDescriptor]
    mov rsi, [fileOffset]
    mov rdx, 0
    mov rax, 8
    syscall

    pop rsi
    pop rdi
    pop rbp
    ret

resizeMem:
    push rbp
    push rdi
    push rsi
    push rdx
    push r10

    mov rdi, [bufferPtr]              # address of old memory block
    mov rsi, [buffer_size]
    mov rdx, rsi
    shl rdx                   # double buffer_size
    mov [buffer_size], rdx    # new buffer_size
    mov r10, 1                # allow reallocation
    mov rax, 25               # syscall 25 (mremap)
    syscall
    
    pop r10
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    ret

searchPattern:
    push rbp
    push rdx
    push rdi
    push rsi
    push r8
    push r9
    
    xor rcx, rcx       # counter
    mov rdx, rdi       # rdx original pattern pointer
    xor r8, r8         # keep track of bytes read to compare with actual
                       # line length
    mov r9, [lineLength]
    
search_loop:           # rdi pattern, rsi buffer
    cmp r8, r9
    je done_searching  # exit condition to respect actual line length
    
    #cmp [rsi], 0      # incompatible operand size
    mov al, [rsi]      # move first byte into al
    cmp al, 0
    
    je done_searching
    #cmp[rsi], [rdi]       # cannot compare two memory locations
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne search_next_byte
    inc rsi                # advance in buffer
    inc rdi                # advance in pattern
    inc r8
    mov al, [rdi]
    cmp al, 0
    #cmp [rdi], 0
    je pattern_found
    jmp search_loop

search_next_byte:
    mov rdi, rdx           # restore pattern pointer
    inc rsi
    inc r8
    jmp search_loop

pattern_found:
    inc rcx
    #lea rdi, [pattern]
    mov rdi, rdx           # restore pattern pointer
    jmp search_loop

done_searching:
    mov rax, rcx

    pop r9
    pop r8
    pop rsi
    pop rdi
    pop rdx
    pop rbp
    ret

endOfProgram:
    pop rbp
    xor rdi, rdi      # Exit status 0
    mov rax, 60       # sys_exit
    syscall


.section .data
#filename:  .asciz "emptyFile.txt"
#filename:   .asciz "fullFile.txt"
#pattern:   .asciz "ex"

fileDescriptor: .quad 0     # store file descriptor
fileOffset:   .quad 0    
bufferPtr:   .quad 0        # store pointer to buffer

occurrences:    .quad 0

buffer_size:    .quad 16   # Store current buffer size (initially 16 bytes)
#bytesRead:    .asciz "Number of bytes read: %d \n"
matches:    .asciz "Number of matches: %d \n"

memAllErr:   .asciz "Error allocating memory\n"
readError:  .asciz "Error reading file\n"
filePrompt: .asciz "Enter file name:\n"
patternPrompt:  .asciz "Enter pattern:\n"

.section .bss

lineLength: .quad
inputFile:  .skip 64
pattern:    .skip 32

# TODO
# - rdx set to 0 in openFile bc we assume the file already exists. TODO
# - handle file creation in the future
# - handle file closing
