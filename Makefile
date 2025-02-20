CC = gcc

.PHONY: clean run debug

all:  grepGod run

grepGod:
	$(CC) -o grepGod -m64 -no-pie grepGod.s 

run:
	./grepGod

clean:
	rm grepGod

debug:
	gdb ./grepGod
