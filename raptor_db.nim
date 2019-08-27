# vim: sw=4 ts=4 sts=4 tw=0 et:

## RaptorDB v0.2 specification.
## Each line is a separate entity. Order of lines does not matter. Lines start with a keyword character,
## depending on that encode:
## - Version: "V\t<float-version_num>"
## - Files: "F\t<int64-file_id>\t<str-file_path>\t<str-file_format>"
## - Sequences: "S\t<int64-seq_id>\t<str-header>\t<int64-seq_len>\t<int64-file_id>\t<int64-start_offset_in_file>\t<int64-data_length>"
## - Blocks: "B\t<int64-block_id>\t<int64-seq_id_start>\t<int64-seq_id_end>\t<int64-num_bases_in_block>"

from algorithm import nil
from math import nil
from sets import nil
from streams import nil
from strformat import fmt
import strutils
import strscans # for Nims `scanf` and `scanp` macros
from parseutils import skipWhitespace, parseBiggestInt
#from ./nuuid import nil
from ./util import nil
import json
import times

type
    # changed the fields to `int`, since otherwise I'd have some trouble with the `scanf` macro, since it
    # uses `parseutils.parseInt` for `$i`. On a 64bit system it's going to be int64 anyways. If `int64` is
    # important, the `scanf` lines need to be changed. Custom matching proc for `$i` for `int64` via
    # `${myParseInt64}`, `parseBiggestInt` in that place works though. See the `block_id` for an example
    # how the code would have to be changed (`const b_frmt` in `load_rdb`)
    SequenceRecord* = object
        seq_id: int
        header*: string
        seq_len: int
        file_id: int
        start_offset_in_file: int
        data_len: int
    FileRecord = tuple
        file_id: int
        file_path: string
        file_format: string
    BlockRecord = tuple
        block_id: int64
        seq_id_start: int
        seq_id_end: int
        num_bases_in_block: int
    Db* = object
        version: string
        files: seq[FileRecord]
        seqs*: seq[SequenceRecord]
        blocks: seq[BlockRecord]

 #proc toSequenceRecord(fields: seq[string]): SequenceRecord =
 #    # should use strutils.parseInt()
 #    result = (fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6])

 #proc writeSequence(sout: File, fields: seq[string]) =
 #    sout.write(
 #        'S', '\t',
 #        fields[1], '\t',
 #        fields[2], '\t',
 #        fields[3], '\t',
 #        fields[4], '\t',
 #        fields[5], '\t',
 #        fields[6], '\n',

type
    SeqLineWriter = object
        num_seq_lines: int
        sout: File
        num_bases_written: int
        block_size: int
        block_start_bases: int
        block_start_id: int
        num_blocks: int

proc initSeqLineWriter(sout: File, block_size_MB: int): SeqLineWriter =
    let block_size = block_size_MB * 1024 * 1024
    return SeqLineWriter(num_seq_lines: 0, sout: sout, num_bases_written: 0,
            block_size: block_size,
        block_start_bases: 0, block_start_id: 0, num_blocks: 0)
proc write_block(w: var SeqLineWriter) =
    let curr_bases_in_block = w.num_bases_written - w.block_start_bases;
    let line = fmt(
            "B\t{w.num_blocks}\t{w.block_start_id}\t{w.num_seq_lines}\t{curr_bases_in_block}\n")
    w.sout.write(line)
    inc w.num_blocks
    w.block_start_id = w.num_seq_lines
    w.block_start_bases = w.num_bases_written
proc write(w: var SeqLineWriter, split_line: seq[string]) =
    # This function updates the sequence IDs depending on the number
    # of already output sequence lines.
    var temp = split_line
    temp[1] = $w.num_seq_lines
    w.sout.write(strutils.join(temp, "\t"))
    w.sout.write('\n')
    inc w.num_seq_lines
    let nbases = strutils.parseBiggestInt(split_line[3])
    w.num_bases_written += nbases.int

    # Write the block if we reached the limit.
    let curr_bases_in_block = w.num_bases_written - w.block_start_bases;
    if curr_bases_in_block >= w.block_size:
        w.write_block()
proc close(w: var SeqLineWriter) =
    w.block_size = 1 # to force the last block if anything has been written
    w.write_block()

# Instead, we will stream-filter.
#
proc stream(sin, sout: File, blacklist: sets.HashSet[string]) =
    let block_size_MB = 1
    var writer = initSeqLineWriter(sout, block_size_MB)
    defer: writer.close()

    for line in lines(sin):
        if len(line) == 0:
            continue
        let keyletter = line[0]
        case keyletter
        of 'V', 'F':
            # Version and File list information.
            sout.write(line)
            sout.write('\n')
            continue
        of 'B':
            # We need to re-block because filtering will
            # reduce the size.
            continue
        of 'S':
            var fields = strutils.splitWhitespace(line)
            assert len(fields) == 7
            if not sets.contains(blacklist, fields[2]):
                writer.write(fields)
                #sout.write(line)
                #sout.write('\n')
            continue
        else:
            let msg = fmt("Unknown line '{line}'")
            #util.raiseEx(msg)
            util.log(msg)
            continue


proc filter*(blacklist_fn: string = "") =
    ## Read/write raptor-db to/from stdin/stdout.
    ## Exclude zmws in blacklist.
    util.log("filter sans ", blacklist_fn)
    var blacklist = sets.initHashSet[string]()
    if len(blacklist_fn) > 0:
        var sin: File
        if not open(sin, blacklist_fn, fmRead):
            util.raiseEx(fmt("Failed to open blacklist file '{blacklist_fn}'"))
        defer: close(sin)
        for zmw in lines(sin):
            util.log(fmt("Skipping ({zmw})"))
            if sets.contains(blacklist, zmw):
                util.raiseEx(fmt(
                        "Found a repeat in blacklist '{blacklist_fn}': '{zmw}'\n Something is wrong!"))
            sets.incl(blacklist, zmw)
    stream(stdin, stdout, blacklist)

const
    MAX_HEADROOM = 1024
#type
#    Headroom = array[MAX_HEADROOM, cchar]

proc load_rdb*(sin: streams.Stream): ref Db =
    stderr.write("BEFORE")
    new(result)
    echo " version init:", result.version
    stderr.write("AFTER")
    #newSeq(result.seqs, 0)
    #var seq_id, seq_len, file_id, offset, data_len: int64
    #var tab: char # to verify that we have read the entire "header"
    var header: string
    # Delimiters should be single tabs, but we accept more in some cases.
    const v_frmt = "V$s$f"
    # first int we match shows how to parse `int64`
    const b_frmt = "B$s${parseBiggestInt}$s$i$s$i$s$i"
    const s_frmt = "S$s$i$s$+$s$i$s$i$s$i$s$i"
    const f_frmt = "F$s$i$s$+$s$+"

    echo "About to iterate over SIN"
    for line in streams.lines(sin):
        echo " in sin"
        echo "len:", len(line)
        echo "line:", line
        # We skip stripping, to be more strict. But we still skip totally blank lines.
        if len(line) == 0:
            continue
        elif line[0] == 'V':
            var ver: float
            let scanned = scanf(line, v_frmt, ver)
            result.version = $ver
            if not scanned:
                let msg = "Too few fields for '" & line & "'"
                raise newException(util.TooFewFieldsError, msg)
        elif line[0] == 'B':
            var br: BlockRecord
            let scanned = scanf(line, b_frmt,
                                br.block_id, br.seq_id_start, br.seq_id_end, br.num_bases_in_block)
            if not scanned:
                let msg = "Too few fields for '" & line & "'"
                raise newException(util.TooFewFieldsError, msg)
        elif line[0] == 'F':
            var fr: FileRecord
            var
              buf0: string
              buf1: string
            let scanned = scanf(line, f_frmt,
                                fr.file_id, buf0, buf1)
            if buf0.len >= (MAX_HEADROOM - 1):
                let msg = "Too many characters in file_path (>1000) for '" & line & "'"
                raise newException(util.FieldTooLongError, msg)
            if buf1.len >= (MAX_HEADROOM - 1):
                let msg = "Too many characters in file_format (>1000) for '" & line & "'"
                raise newException(util.FieldTooLongError, msg)
            if not scanned:
                let msg = "Too few fields for '" & line & "'"
                raise newException(util.TooFewFieldsError, msg)
            #toString(buf0, fr.file_path)
            #toString(buf1, fr.file_format)
        elif line[0] == 'S':
            var sr: SequenceRecord
            var buf0: string
            var idx = 0
            var
              seqid: string
              seqLen: string
              fileID: string
              startOffsetInFile: string
              dataLen: string
            # this is kinda ugly, because using scanf I can't make it work and here we have to define
            # all those string locals, add the integers and only then convert to ints later
            let scanned = scanp(line, idx, "S", skipWhitespace($input, idx), +({'0'..'9'} -> seqid.add($_)),
                                skipWhitespace($input, idx), +({'a'..'z', 'A'..'Z', '_', '0'..'9', '/'} -> buf0.add($_)),
                                skipWhitespace($input, idx), +({'0'..'9'} -> seqLen.add($_)),
                                skipWhitespace($input, idx), +({'0'..'9'} -> fileID.add($_)),
                                skipWhitespace($input, idx), +({'0'..'9'} -> startOffsetInFile.add($_)),
                                skipWhitespace($input, idx), +({'0'..'9'} -> dataLen.add($_)))
            sr.seq_id = seqID.parseInt
            sr.seq_len = seqLen.parseInt
            sr.fileId = fileId.parseInt
            sr.start_offset_in_file = startOffsetInFile.parseInt
            sr.data_len = dataLen.parseInt
            if buf0.len >= (MAX_HEADROOM - 1):
                let msg = "Too many characters in header (>1000) for '" & line & "'"
                raise newException(util.FieldTooLongError, msg)
            echo " if'd"
            if not scanned:
                let msg = "Too few fields for '" & line & "'"
                raise newException(util.TooFewFieldsError, msg)
            echo " if'd again"
            sr.header = buf0
            # toString(buf0, sr.header)
            echo " sr:", sr
            echo " sr.header:", sr.header
            echo " len(seqs) before add", len(result.seqs)
            result.seqs.add(sr)
            echo "len:", len(result.seqs)
        echo " Iter to next line"

proc get_length_cutoff*(rdb_stream: streams.Stream, genome_size: int64,
        coverage: float, fail_low_cov: bool = false,
        alarms_file: string = ""): int64 =
    # The defaults here are only to help with tests.
    echo "A"
    assert coverage > 0, fmt"Coverage needs to be > 0. Provided value: coverage = {coverage}"
    echo "B"
    let msg = fmt"Genome size needs to be > 0. Provided value: genome_size = {genome_size}"
    echo "B0:"
    echo "B1:", msg
    assert genome_size > 0, fmt"Genome size needs to be > 0. Provided value: genome_size = {genome_size}"
    echo "C"

    let db = load_rdb(rdb_stream)
    echo "D"
    let seqs = algorithm.sorted(db.seqs) do (a, b: SequenceRecord) -> int:
        return cmp(b.seq_len, a.seq_len)
    echo "E"

    let min_desired_size = math.ceil(genome_size.float * coverage).int64
    var sum_sizes: int64 = 0
    var last_size: int64 = 0

    for sq in seqs:
        last_size = sq.seq_len
        sum_sizes += last_size
        #echo fmt"{sq.seq_len} {last_size} {sum_sizes}"
        if sum_sizes >= min_desired_size:
            echo "Early returning!"
            return last_size # Success!

    if fail_low_cov:
        let msg = fmt"Not enough reads available for desired genome coverage (bases needed={min_desired_size} > actual={sum_sizes})"
        echo "Raising util.GenomeCoverageError!"
        raise newException(util.GenomeCoverageError, msg)
    echo "NOT RAISING!"
    return last_size # This is N100, aka the min.


proc alarm(e: ref Exception, fn: string) =
    ## Write a special JSON object expected by pbcommand.models.common.
    var fout = open(fn, fmWrite)
    if nil == fout:
        util.raiseEx("Could not open '" & fn & "' for write.")
    defer: fout.close()
    let uuid = 999 #nuuid.generateUUID()
    let createdAt = $times.now().utc() #datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
 # this is propagated to SMRT Link UI
 # see PacBioAlarm class in pbcommand.models.common for details -- nat
    let alarms = %* [
        {
            "exception": $e.name,
            "info": "",
            "message": $e.msg,
            "name": $e.name,
            "severity": "ERROR",
            "owner": "TAG",
            "createdAt": createdAt,
            "id": uuid,
        }
    ]
    fout.write($alarms & "\n")


proc calc_length_cutoff*(rdb_fn: string = "rawreads.db",
        genome_size: int64 = 4600000, coverage: float = 30,
        fail_low_cov: bool = false, alarms_fn: string = "") =
    ## Perform a linear pass on an overlap file, and determine rough clipping coordinates to 'correct' reads.
    ## Write integer to stdout.
    try:
        let content = system.readFile(rdb_fn) # read into memory b/c streams lib is slow
        var sin = streams.newStringStream(content)
        defer: streams.close(sin)

        let cutoff = get_length_cutoff(sin, genome_size, coverage, fail_low_cov, alarms_fn)
        stdout.write($cutoff & "\n")
    except Exception as exc:
        if "" != alarms_fn:
            alarm(exc, alarms_fn)
        raise
