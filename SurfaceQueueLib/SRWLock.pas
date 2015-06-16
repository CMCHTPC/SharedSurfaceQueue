unit SRWLock;

interface

type

    { TSRWLock }

    TSRWLock = class
    private
        FLock: Pointer;
    public
        constructor Create;
        procedure AcquireShared;
        procedure ReleaseShared;
        procedure AcquireExclusive;
        procedure ReleaseExclusive;
    end;

implementation

procedure AcquireSRWLockShared(var P: Pointer); stdcall;
    external 'kernel32.dll' Name 'AcquireSRWLockShared';
procedure ReleaseSRWLockShared(var P: Pointer); stdcall;
    external 'kernel32.dll' Name 'ReleaseSRWLockShared';

procedure AcquireSRWLockExclusive(var P: Pointer); stdcall;
    external 'kernel32.dll' Name 'AcquireSRWLockExclusive';
procedure ReleaseSRWLockExclusive(var P: Pointer); stdcall;
    external 'kernel32.dll' Name 'ReleaseSRWLockExclusive';

procedure InitializeSRWLock(var p: Pointer); stdcall;
    external 'kernel32.dll' Name 'InitializeSRWLock';

{ TSRWLock }

constructor TSRWLock.Create;
begin
    InitializeSRWLock(FLock);
end;



procedure TSRWLock.AcquireShared;
begin
    AcquireSRWLockShared(FLock);
end;



procedure TSRWLock.ReleaseShared;
begin
    ReleaseSRWLockShared(FLock);
end;



procedure TSRWLock.AcquireExclusive;
begin
    AcquireSRWLockExclusive(FLock);
end;



procedure TSRWLock.ReleaseExclusive;
begin
    ReleaseSRWLockExclusive(FLock);
end;

end.
