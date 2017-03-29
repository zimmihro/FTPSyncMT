unit Logfile;

interface

uses SysUtils, Classes,
  DB, IniFiles,
  ADODB, // JvExDBGrids,
  Masks,
  IdMessage, IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient,
  IdExplicitTLSClientServerBase, IdMessageClient, IdSMTPBase, IdSMTP,
  Generics.Collections;

type
  TLoglevel = (LOG_ERRORS, LOG_WARNINGS, LOG_HINTS, LOG_ALL);

  /// Ist ein Eintrag für den Log. Enthält nen Text, einen Zeitstempel und eine Priorität
type
  TLogItem = class
  private
    ItemText: string;
    ItemTime: TDatetime;
    ItemPriority: TLoglevel;
  public
    constructor CreateLogItem(text: string; prior: TLoglevel); overload;
    constructor CreateLogItem(text: string; prior: TLoglevel;
      time: TDate); overload;
    function getItemPriority(): TLoglevel;
  end;

type
  TLog = class

  private
    Log: TextFile;
    Logname: string;
    Logpath: string;
    Loglevel: TLoglevel;
    LogItems: TList<TLogItem>;
    SMTP: TIdSMTP;
    Mail: TIdMessage;
    InstantWrite: boolean;
    TimeLogging: boolean;
    finalized: boolean;

    procedure WriteLog(item: TLogItem);

  public
    constructor CreateLogFile(path: string; name: string;
      writeinstant: boolean); overload;
    constructor CreateLogFile(path: string; name: string; writeinstant: boolean;
      level: TLoglevel); overload;
    destructor DestroyLogFile();
    procedure SetLogname(name: string);
    procedure SetLogPath(path: string);
    procedure SetLogLevel(level: TLoglevel);
    procedure SetMail(email: TIdMessage; recipients: string);
    procedure SetMailCC(CC: string);
    procedure SetSMTP(sm: TIdSMTP);
    procedure AddItem(item: TLogItem); overload;
    procedure AddItem(messge: string; prior: TLoglevel); overload;
    function FinalizeLog(level: TLoglevel): boolean;
    function getLogName(): string;
    function getItemCount(level: TLoglevel): integer;
    function getLogLevel(): TLoglevel;
    function SendMail(subject: string; pretext: string): boolean;
  end;

implementation

constructor TLogItem.CreateLogItem(text: string; prior: TLoglevel);
begin
  inherited Create;
  ItemText := text;
  ItemTime := now;
  ItemPriority := prior;
end;

constructor TLogItem.CreateLogItem(text: string; prior: TLoglevel; time: TDate);
begin
  inherited Create;
  ItemText := text;
  ItemTime := time;
  ItemPriority := prior;
end;

function TLogItem.getItemPriority: TLoglevel;
begin
  result := self.ItemPriority;
end;

/// /////////////////////////////////////////////////////////////////////////////////////////////////////////////
// TLog
/// /////////////////////////////////////////////////////////////////////////////////////////////////////////////

constructor TLog.CreateLogFile(path: string; name: string;
  writeinstant: boolean);
begin
  inherited Create;
  LogItems := TList<TLogItem>.Create;
  Logpath := path;
  Loglevel := TLoglevel.LOG_ALL;
  finalized := false;
  if not DirectoryExists(Logpath) then
    try
      MkDir(Logpath);
    except
    end; // TODO  fehlerbehandlung
  Logname := name + '.log';
  InstantWrite := writeinstant;
  TimeLogging := true;
  AssignFile(Log, Logpath + Logname);
  try
    Rewrite(Log);
  except
  end; // TODO      fehlerbehandlung
  self.AddItem(TLogItem.CreateLogItem('Info - Log erstellt', LOG_ALL));
end;

constructor TLog.CreateLogFile(path: string; name: string;
  writeinstant: boolean; level: TLoglevel);
begin
  inherited Create;
  LogItems := TList<TLogItem>.Create;
  Logpath := path;
  finalized := false;
  if not DirectoryExists(Logpath) then
    try
      MkDir(Logpath);
    except
    end; // TODO  fehlerbehandlung
  Logname := name + '.log';
  AssignFile(Log, Logpath + Logname);
  try
    Rewrite(Log);
    CloseFile(Log);
  except
  end; // TODO      fehlerbehandlung
  Loglevel := level;
  InstantWrite := writeinstant;
  TimeLogging := true;
  self.AddItem(TLogItem.CreateLogItem('Hinweis: - Log erstellt', LOG_HINTS));
end;

destructor TLog.DestroyLogFile;
begin
  if InstantWrite AND not finalized then
    FinalizeLog(self.Loglevel);
  self.LogItems.Clear;
  self.LogItems.Free;
end;

procedure TLog.AddItem(item: TLogItem);
begin
  LogItems.Add(item);
  if InstantWrite then
    WriteLog(item);
end;

procedure TLog.AddItem(messge: string; prior: TLoglevel);
begin
  self.AddItem(TLogItem.CreateLogItem(messge, prior));
end;

procedure TLog.WriteLog(item: TLogItem);
begin
  // AssignFile(Log, Logpath+Logname);
  try
    Append(Log);
  except
  end; // TODO      fehlerbehandlung
  if TimeLogging then
    Writeln(Log, item.ItemText + ' @ ' + DateToStr(item.ItemTime) + ' ' +
      TimeToStr(item.ItemTime))
  else
    Writeln(Log, item.ItemText);
  try
    CloseFile(Log);
  except
  end; // TODO fehlerbehandlung
end;

function TLog.getItemCount(level: TLoglevel): integer;
var
  i: integer;
  tempitem: TLogItem;
begin
  result := 0;
  try
    for i := 0 to LogItems.Count - 1 do
    begin
      tempitem := LogItems.Items[i];
      if tempitem.getItemPriority = level then
        inc(result);
    end;
  finally

  end;
end;

function TLog.FinalizeLog(level: TLoglevel): boolean;
var
  i: integer;
begin
  if not InstantWrite then
  begin
    try
      Append(Log);
      for i := 0 to LogItems.Count - 1 do
      begin
        if LogItems[i].ItemPriority <= level then
        begin
          if TimeLogging then
            Writeln(Log, DateToStr(LogItems[i].ItemTime) + ' ' +
              TimeToStr(LogItems[i].ItemTime) + ' ' + LogItems[i].ItemText)
          else
            Writeln(Log, LogItems[i].ItemText);
        end;

      end;
      result := true;
      finalized := true;
      CloseFile(Log);
    except
      result := false;
    end;
  end
  else
    result := false;
end;

{
  Getter und Setter
}

procedure TLog.SetLogname(name: string);
begin
  Logname := name;
end;

procedure TLog.SetLogPath(path: string);
begin
  Logpath := path;
end;

procedure TLog.SetLogLevel(level: TLoglevel);
begin
  Loglevel := level;
end;

procedure TLog.SetMail(email: TIdMessage; recipients: string);
var
  maillist: TStringList;
  i: integer;
begin
  maillist := TStringList.Create;
  try
    Mail := email;
    maillist.Delimiter := ',';
    maillist.DelimitedText := recipients;
    for i := 0 to maillist.Count - 1 do
      if MatchesMask(maillist[i],
        '[A-Z0-9]*[A-Z0-9]@[A-Z0-9]*[A-Z0-9].[A-Z0-9]*') then
        Mail.recipients.Add.Address := maillist[i];
  finally
    maillist.Free;
  end;
end;

procedure TLog.SetMailCC(CC: string);
var
  maillist: TStringList;
  i: integer;
begin
  maillist := TStringList.Create;
  try
    maillist.Delimiter := ',';
    maillist.DelimitedText := CC;
    for i := 0 to maillist.Count - 1 do
      if MatchesMask(maillist[i],
        '[A-Z0-9]*[A-Z0-9]@[A-Z0-9]*[A-Z0-9].[A-Z0-9]*') then
        Mail.CCList.Add.Address := maillist[i];
  finally
    maillist.Free;
  end;
end;

procedure TLog.SetSMTP(sm: TIdSMTP);
begin
  SMTP := sm;
end;

function TLog.getLogName(): string;
begin
  result := self.Logname;
end;

function TLog.getLogLevel;
begin
  result := self.Loglevel;
end;

function TLog.SendMail(subject: string; pretext: string): boolean;
var
  i: integer;
begin
  Mail.subject := subject;
  Mail.Body.Add(pretext);
  Mail.From.Address := 'server@mtronline.de';
  Mail.From.Name := 'Laufzeitbericht';
  if not self.InstantWrite then
  begin
    Mail.Body.Add('Fehler: ' +
      InttoStr(self.getItemCount(TLoglevel.LOG_ERRORS)));
    if self.Loglevel < TLoglevel.LOG_WARNINGS then
      Mail.Body.Add('Warnungen: ' +
        InttoStr(self.getItemCount(TLoglevel.LOG_WARNINGS)));
    if self.Loglevel < TLoglevel.LOG_HINTS then
      Mail.Body.Add('Hinweise: ' +
        InttoStr(self.getItemCount(TLoglevel.LOG_HINTS)));
  end;
  try
    for i := 0 to LogItems.Count - 1 do
    begin
      if LogItems[i].ItemPriority <= self.Loglevel then
      begin
        if TimeLogging then
          Mail.Body.Add(DateToStr(LogItems[i].ItemTime) + ' ' +
            TimeToStr(LogItems[i].ItemTime) + ' ' + LogItems[i].ItemText)
        else
          Mail.Body.Add(LogItems[i].ItemText);
      end;
    end;
     SMTP.Connect;
      SMTP.Send(Mail);
      SMTP.DisconnectNotifyPeer;
    result := true
  except
    result := false;
  end;

end;

end.
