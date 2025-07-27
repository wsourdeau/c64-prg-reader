program PrgReader;

{$CODEPAGE UTF8}
{$TYPEDADDRESS ON}
{$R+}

uses
    {$IFDEF WINDOWS}
    Windows,
    {$ENDIF}
    SysUtils;

type
    ProgramOptions = record
        filename, listingFormat: string;
        helpMode, infoMode: boolean;
    end;

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
    HelpOption = '--help';
    InfoOption = '--info';
    ListingFmtOption = '--listing-fmt';
    UnknownOptionPrefix = '--';
    Tokens: Array of UTF8String = ('END', 'FOR', 'NEXT', 'DATA',
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

function GetToken(code: Byte): UTF8String;
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
        Die('not enough space left for ' + Format('%d', [length]) + ' bytes.');
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
        Die('line does not end with 0.');
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
        if bLine.nextAddr < currentAddr then
            Die('newLine.nextAddr < currentAddr');
        if bLine.nextAddr > (currentAddr + 100) then
            Die('dubious address further from current by 100 bytes:' +
                    ' current=' + format('%.4x', [currentAddr]) +
                    ' next=' + format('%.4x', [bLine.nextAddr]));
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
        Die('reached the end of the program.');
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
        currentAddr := newLine.nextAddr;
    end;

    bPrg.fileSize := bBuffer.size;
    if (pState.pos > bBuffer.size) then
        Die('"pos" overflowed the buffer size');
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

function DecodeLine(rawLine: ByteBuffer): UTF8String;
var
    pState: ParseState;
    currentByte: Byte;
    decodedLine, word: UTF8String;
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

function GetMachineModel(startAddr: Word): string;
begin
    if startAddr = $0801 then
        GetMachineModel := 'C64 (basic v2)'
    else if startAddr = $1001 then
        GetMachineModel := 'C16 or Plus/4'
    else if startAddr = $1201 then
        GetMachineModel := 'VIC-20'
    else if startAddr = $1c01 then
        GetMachineModel := 'C128'
    else
        GetMachineModel := 'Unknown';
end;

function IsCompiledPrg(bPrg: BasicPrg): boolean;
var
    rawLine: ByteBuffer;
    tokenChar: Byte;
    instruction: string;
begin
    IsCompiledPrg := false;
    if bPrg.nbrLines = 1 then
    begin
        rawLine := bPrg.basicLines[0].rawLine;
        if rawLine.size > 3 then
        begin
            tokenChar := rawLine.data[2];
            instruction := GetToken(tokenChar);
            if instruction = 'SYS' then
                IsCompiledPrg := true;
        end;
    end;
end;

procedure PrintPrgInfos(filename: string; bPrg: BasicPrg);
begin
    writeln('# ', ExtractFilename(filename));
    writeln();
    writeln('## Infos');
    writeln();
    writeln('* File size: ', bPrg.fileSize, ' bytes');
    writeln('* Start address: ', format('0x%.4X', [bPrg.startAddr]));
    writeln('* Machine Model: ', GetMachineModel(bPrg.startAddr));
    if (IsCompiledPrg(bPrg)) then
        writeln('* Program is really a compiled program');
    writeln('* Lines of BASIC code: ', bPrg.nbrLines);
    writeln('* Remaining after BASIC code: ', bPrg.remainingBytes, ' bytes');
    writeln();
    writeln('## BASIC program (', bPrg.nbrLines, ' lines)');
    writeln();
end;

procedure PrintBasicPrg(bPrg: BasicPrg; options: ProgramOptions);
var
    bLine: BasicLine;
    i: LongInt;
    decodedLine: string;
    showTicks: boolean;
begin
    showTicks := options.infoMode and (options.listingFormat = 'markdown');
    if showTicks then
        writeln('```pascal');
    for i := 0 to LongInt(bPrg.nbrLines - 1) do
    begin
        bLine := bPrg.basicLines[i];
        if bLine.nextAddr = 0 then
            Die('reached the end of the program.');
        decodedLine := DecodeLine(bLine.rawLine);
        if decodedLine[1] = Char(13) then
            writeln('unexpected character.');
        writeln(decodedLine);
    end;
    if showTicks then
        writeln('```');
end;

function ParseProgramOptions(): ProgramOptions;
var
    i: integer;
begin
    ParseProgramOptions.listingFormat := 'raw';
    ParseProgramOptions.helpMode := false;
    ParseProgramOptions.infoMode := false;
    ParseProgramOptions.filename := '';

    for i := 1 to ParamCount do
    begin
        if ParamStr(i) = HelpOption then
            ParseProgramOptions.helpMode := true
        else if ParamStr(i) = InfoOption then
            ParseProgramOptions.infoMode := true
        else if LeftStr(ParamStr(i), Length(ListingFmtOption) + 1) = ListingFmtOption + '=' then
            ParseProgramOptions.listingFormat := RightStr(ParamStr(i),
                                                          Length(ParamStr(i)) - (Length(ListingFmtOption) + 1))
        else if LeftStr(ParamStr(i), 2) = UnknownOptionPrefix then
            Die('unknown option: ' + ParamStr(i))
        else
            ParseProgramOptions.filename := ParamStr(i);
    end;
end;

var
    options: ProgramOptions;
    bBuffer: ByteBuffer;
    bPrg: BasicPrg;
begin;
    {$IFDEF WINDOWS}
    SetConsoleOutputCP(CP_UTF8);
    {$ENDIF}

    options := ParseProgramOptions();
    if options.helpMode then
    begin
        writeln('c64-prg-reader --help  or  c64-prg-reader [options] filename');
        writeln('Options:');
        writeln('  --help                  display this help');
        writeln('  --info                  display information about the file'
                    + ' in addition to the source code');
        writeln('  --listing-fmt=[format]  format the source code according to'
                    + ' ''format'' (*raw, markdown)');
    end
    else if options.filename = '' then
        Die('missing filename parameter.')
    else
    begin
        bBuffer := ReadFile(options.filename);
        bPrg := ParseBasicPrg(bBuffer);
        if options.infoMode then
            PrintPrgInfos(options.filename, bPrg);
        PrintBasicPrg(bPrg, options);
        FreeMem(bBuffer.data);
    end
end.
