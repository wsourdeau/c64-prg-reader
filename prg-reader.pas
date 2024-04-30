program PrgReader;

{$TYPEDADDRESS ON}
{$R+}

type
    ByteBuffer = record
        data: PByte;
        size: integer;
    end;
    ParseState = record
        bBuffer: ByteBuffer;
        pos: integer;
    end;
    BasicLine = record
        nextAddr: integer;
        rawLine: ByteBuffer;
    end;
    BasicPrg = record
        startAddr: integer;
        nbrLines: integer;
        maxLines: integer;
        basicLines: array of BasicLine;
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
    idx := code and $7f;
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

procedure EnsureSizeLeft(var pState: ParseState; size: integer);
begin
    if pState.pos + size > pState.bBuffer.size then
        Die('Not enough space left.');
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
    EnsureSizeLeft(pState, sizeOf(integer));
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

function ReadBasicLine(var pState: ParseState; currentAddr: integer): BasicLine;
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
        bLine.rawLine.size := bLine.nextAddr - currentAddr - 2;
        EnsureLineEndsWith0(bLine.rawLine);
        Inc(pState.pos, bLine.rawLine.size);
    end;

    ReadBasicLine := bLine;
end;

procedure AddLine(var bPrg: BasicPrg; newLine: BasicLine);
var
    newMaxLines: integer;
begin;
    if newLine.nextAddr = 0 then
        Die('Reached the end of the program.');
    if bPrg.nbrLines = bPrg.maxLines then
    begin
        newMaxLines := bPrg.maxLines * 2;
        SetLength(bPrg.basicLines, newMaxLines);
        bPrg.maxLines := newMaxLines;
    end;
    bPrg.basicLines[bPrg.nbrLines] := newLine;
    Inc(bPrg.nbrLines);
end;

function ParseBasicPrg(bBuffer: ByteBuffer): BasicPrg;
var
    bPrg: BasicPrg;
    currentAddr: integer;
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

    ParseBasicPrg := bPrg;
end;

function ReadFile(filename: string): ByteBuffer;
var
    prgFile: File;
    bBuffer: ByteBuffer;
begin
    Assign(prgFile, filename);
    Reset(prgFile, 1);
    bBuffer.size := FileSize(prgFile);
    bBuffer.data := GetMem(SizeOf(Byte) * bBuffer.size);
    BlockRead(prgFile, bBuffer.data^, bBuffer.size - 1);
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

procedure PrintBasicPrg(bPrg: BasicPrg);
var
    bLine: BasicLine;
    i: integer;
    decodedLine: string;
begin
    // writeln('start address: ', format('%x', [bPrg.startAddr]));
    // writeln('line count: ', bPrg.nbrLines);
    for i := 0 to bPrg.nbrLines - 1 do
    begin
        bLine := bPrg.basicLines[i];
        if bLine.nextAddr = 0 then
            Die('Reached the end of the program.');
        decodedLine := DecodeLine(bLine.rawLine);
        if decodedLine[1] = Char(13) then
            writeln('Unexpected character.');
        writeln(decodedLine);
        // writeln('next address: ' + format('%x', [bLine.nextAddr]) + '|' + decodedLine);
    end;
    // writeln('(end of program)');
end;

var
    bBuffer: ByteBuffer;
    bPrg: BasicPrg;
begin;
    if ParamCount > 0 then
    begin
        bBuffer := ReadFile(ParamStr(1));
        bPrg := ParseBasicPrg(bBuffer);
        PrintBasicPrg(bPrg);
        FreeMem(bBuffer.data);
    end;
end.
