#F:=--gc:none
#F:=--gc:refc
F+=-d:useSysAssert #-d:useGcAssert
F+=--debugger:native
#F:=--newruntime

all:
	nim c $F -r t_raptor_db.nim
