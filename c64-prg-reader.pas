program PrgReader;

uses SysUtils;

{$TYPEDADDRESS ON}
{$R+}

type
    ByteBuffer = record
        data: PByte;
        size: Word;
    end;
    ParseState = record
        bBuffer: ByteBuffer;
        pos: Word;
    end;
    BasicLine = record
        nextAddr: Word;
        rawLine: ByteBuffer;
    end;
    BasicPrg = record
        startAddr: Word;
        nbrLines: LongInt;
        maxLines: LongInt;
        basicLines: array of BasicLine;
        fileSize : Word;
        remainingBytes : Word;
    end;

const
    Tokens: Array of string = ('END', 'FOR', 'NEXT', 'DATA',
                               'INPUT#', 'INPUT', 'DIM', 'READ',
                               'LET', 'GOTO', 'RUN', 'IF', 'RESTORE',
                               'GOSUB', 'RETURN', 'REM', 'STOP',
                               'ON', 'WAIT', 'LOAD', 'SAVE',
                               'VERIFY', 'DEF', 'POKE', 'PRINT#',
                               'PRINT', 'CONT', 'LIST', 'CLR', 'CMD',
                               'SYS', 'OPEN', 'CLOSE', 'GET', 'NEW',
                               'TAB(', 'TO', 'FN', 'SPC(', 'THEN',
                               'NOT', 'STEP', '+', '-', '*', '/',
                               '^', 'AND', 'OR', '>', '=', '<',
                               'SGN', 'INT', 'ABS', 'USR', 'FRE',
                               'POS', 'SQR', 'RND', 'LOG', 'EXP',
                               'COS', 'SIN', 'TAN', 'ATN', 'PEEK',
                               'LEN', 'STR$', 'VAL', 'ASC', 'CHR$',
                               'LEFT$', 'RIGHT$', 'MID$');

function GetToken(code: Byte): string;
var
    idx: Byte;
    nbrStr: string;
begin
    idx := code and Byte($7f);
    if idx < Length(Tokens) then
        GetToken := Tokens[idx]
    else
    begin
        Str(idx, nbrStr);
        GetToken := '[unknown: ' + nbrStr + ']';
    end;
end;

procedure Die(message: string);
begin
    writeln('Error: ' + message);
    Halt(-1);
end;

procedure EnsureSizeLeft(var pState: ParseState; length: Word);
begin
    if pState.pos + length > pState.bBuffer.size then
        Die('Not enough space left for ' + Format('%d', [length]) + ' bytes.');
end;

function ReadByte(var pState: ParseState): Byte;
var
    bytePtr: PByte;
begin
    EnsureSizeLeft(pState, sizeOf(Byte));
    bytePtr := pState.bBuffer.data + pState.pos;
    ReadByte := bytePtr^;
    Inc(pState.pos);
end;

function ReadWord(var pState: ParseState): Word;
var
    bytePtr: PByte;
begin
    EnsureSizeLeft(pState, sizeOf(Word));
    bytePtr := pState.bBuffer.data + pState.pos;
    ReadWord := PWord(bytePtr)^;
    Inc(pState.pos, 2);
end;

procedure EnsureLineEndsWith0(line: ByteBuffer);
var
    endData: PByte;
begin
    endData := line.data + line.size - 1;
    if endData^ <> 0 then
        Die('Line does not end with 0.');
end;

function ReadBasicLine(var pState: ParseState; currentAddr: Word): BasicLine;
var
    bLine: BasicLine;
begin
    bLine.nextAddr := ReadWord(pState);
    if bLine.nextAddr = 0 then
    begin
        bLine.rawLine.data := nil;
        bLine.rawLine.size := 0;
    end
    else
    begin
        bLine.rawLine.data := pState.bBuffer.data + pState.pos;
        bLine.rawLine.size := Word(bLine.nextAddr - currentAddr - 2);
        EnsureLineEndsWith0(bLine.rawLine);
        Inc(pState.pos, bLine.rawLine.size);
    end;

    ReadBasicLine := bLine;
end;

procedure AddLine(var bPrg: BasicPrg; newLine: BasicLine);
var
    newMaxLines: LongInt;
begin;
    if newLine.nextAddr = 0 then
        Die('Reached the end of the program.');
    if bPrg.nbrLines = bPrg.maxLines then
    begin
        newMaxLines := LongInt(bPrg.maxLines * 2);
        SetLength(bPrg.basicLines, newMaxLines);
        bPrg.maxLines := newMaxLines;
    end;
    bPrg.basicLines[bPrg.nbrLines] := newLine;
    Inc(bPrg.nbrLines);
end;

function ParseBasicPrg(bBuffer: ByteBuffer): BasicPrg;
var
    bPrg: BasicPrg;
    currentAddr: Word;
    pState: ParseState;
    newLine: BasicLine;
begin
    pState.bBuffer := bBuffer;
    pState.pos := 0;
    bPrg.startAddr := ReadWord(pState);
    bPrg.nbrLines := 0;
    bPrg.maxLines := 64;
    SetLength(bPrg.basicLines, bPrg.maxLines);

    currentAddr := bPrg.startAddr;
    while currentAddr <> 0 do
    begin
        newLine := ReadBasicLine(pState, currentAddr);
        if newLine.nextAddr <> 0 then
            AddLine(bPrg, newLine);
        currentAddr := newLine.nextAddr
    end;

    bPrg.fileSize := bBuffer.size;
    if (pState.pos > bBuffer.size) then
        Die ('"pos" overflowed the buffer size');
    bPrg.remainingBytes := Word(bBuffer.size - pState.pos);

    ParseBasicPrg := bPrg;
end;

function ReadFile(filename: string): ByteBuffer;
var
    prgFile: File;
    bBuffer: ByteBuffer;
begin
    Assign(prgFile, filename);
    Reset(prgFile, 1);
    bBuffer.size := Word(FileSize(prgFile));
    bBuffer.data := GetMem(PtrUInt(SizeOf(Byte) *  bBuffer.size));
    BlockRead(prgFile, bBuffer.data^, Int64(bBuffer.size));
    Close(prgFile);
    ReadFile := bBuffer;
end;

function DecodeLine(rawLine: ByteBuffer): string;
var
    pState: ParseState;
    currentByte: Byte;
    decodedLine, word: string;
    quoted: boolean;
begin
    pState.bBuffer := rawLine;
    pState.pos := 0;

    quoted := false;

    Str(ReadWord(pState), decodedLine);
    decodedLine := decodedLine + ' ';
    while pState.pos < (pState.bBuffer.size - 1) do
    begin
        currentByte := ReadByte(pState);
        if currentByte = Byte('"') then
            quoted := not quoted;
        if (currentByte > $7f) and not quoted then
        begin
            word := GetToken(currentByte);
            decodedLine := decodedLine + word;
        end
        else
            decodedLine := decodedLine + Char(currentByte);
    end;

    DecodeLine := decodedLine;
end;

procedure PrintBasicPrg(bPrg: BasicPrg; infoMode: boolean);
var
    bLine: BasicLine;
    i: LongInt;
    decodedLine: string;
begin
    if infoMode then
    begin
         writeln('start address: ', format('0x%X', [bPrg.startAddr]));
         writeln('line count: ', bPrg.nbrLines);
         writeln('(beginning of program)');
    end;
    for i := 0 to LongInt(bPrg.nbrLines - 1) do
    begin
        bLine := bPrg.basicLines[i];
        if bLine.nextAddr = 0 then
            Die('Reached the end of the program.');
        decodedLine := DecodeLine(bLine.rawLine);
        if decodedLine[1] = Char(13) then
            writeln('Unexpected character.');
        writeln(decodedLine);
    end;
    if infoMode then
    begin
        writeln('(end of program)');
        writeln('file size: ', bPrg.fileSize);
        writeln('remaining bytes: ', bPrg.remainingBytes);
    end;

end;

var
    bBuffer: ByteBuffer;
    bPrg: BasicPrg;
    i: LongInt;
    helpMode, infoMode: boolean;
    filename: string;
begin;
    helpMode := false;
    infoMode := false;
    filename := '';

    for i := 1 to ParamCount do
    begin
        if ParamStr(i) = '--help' then
            helpMode := true
        else if ParamStr(i) = '--info' then
            infoMode := true
        else if LeftStr(ParamStr(i), 2) = '--' then
            writeln('Unknown option: ', ParamStr(i))
        else
            filename := ParamStr(i);
    end;

    if helpMode then
    begin
        writeln('c64-prg-reader --help  or  c64-prg-reader [options] filename');
        writeln('Options:');
        writeln('  --help    display this help');
        writeln('  --info    display information about the file in addition to the source code');
    end
    else if filename = '' then
        writeln('Missing filename parameter.')
    else
    begin
        bBuffer := ReadFile(filename);
        bPrg := ParseBasicPrg(bBuffer);
        PrintBasicPrg(bPrg, infoMode);
        FreeMem(bBuffer.data);
    end
end.
