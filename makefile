#F:=--gc:none
#F:=--gc:refc
#F+=-d:useSysAssert  # causes: missing cstderr lib/system.nim
#-d:useGcAssert
F+=--debugger:native
F+=--newruntime
F+=--showAllMismatches:on

all:
	nim c $F -r t_raptor_db.nim
