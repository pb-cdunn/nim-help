# vim: sts=4:ts=4:sw=4:et:tw=0
#from cpuinfo import nil
from os import nil
#from threadpool import nil

type PbError* = object of Exception
type GenomeCoverageError* = object of PbError
type FieldTooLongError* = object of PbError
type TooFewFieldsError* = object of PbError

proc raiseEx*(msg: string) {.discardable.} =
    raise newException(PbError, msg)

proc isEmptyFile*(fn: string): bool =
    var finfo = os.getFileInfo(fn)
    if finfo.size == 0:
        return true
    return false

template withcd*(newdir: string, statements: untyped) =
    let olddir = os.getCurrentDir()
    os.setCurrentDir(newdir)
    defer: os.setCurrentDir(olddir)
    statements

proc log*(words: varargs[string, `$`]) =
    for word in words:
        write(stderr, word)
    write(stderr, '\l')

proc adjustThreadPool*(n: int) =
    ## n==0 => use ncpus
    ## n==-1 => do not alter threadpool size (to avoid a weird problem for now)
    log("(ThreadPool is currently not used.)")
    #var size = n
    #if n == 0:
    #    size = cpuinfo.countProcessors()
    #if size > threadpool.MaxThreadPoolSize:
    #    size = threadpool.MaxThreadPoolSize
    #if size == -1:
    #    log("ThreadPoolsize=", size,
    #        " (i.e. do not change)",
    #        ", MaxThreadPoolSize=", threadpool.MaxThreadPoolSize,
    #        ", NumCpus=", cpuinfo.countProcessors())
    #    return
    #log("ThreadPoolsize=", size,
    #    ", MaxThreadPoolSize=", threadpool.MaxThreadPoolSize,
    #    ", NumCpus=", cpuinfo.countProcessors())
    #threadpool.setMaxPoolSize(size)

iterator walk*(dir: string, followlinks = false, relative = false): string =
    ## similar to python os.walk(), but always topdown and no "onerror"
    let followFilter = if followLinks: {os.pcDir, os.pcLinkToDir} else: {os.pcDir}
    let yieldFilter = {os.pcFile, os.pcLinkToFile}
    for p in os.walkDirRec(dir, yieldFilter = yieldFilter,
            followFilter = followFilter, relative = relative):
        yield p
