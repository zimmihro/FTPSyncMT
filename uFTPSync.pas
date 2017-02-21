unit uFTPSync;

interface

procedure SyncLocalToFTP(localfolder, ftpurl: string; ftpfolder: string; login, password: string);

implementation

uses idFTP, classes, sysutils, iduri, Generics.Collections, Generics.Defaults, Windows,
  StrUtils, IdFTPList, IdAllFTPListParsers;

type
  TLocalFile = class;

  TFTPFile = class
  private
    FFileName   : string;
    FDescription: string;
    FPath       : string;
    FContent    : TMemoryStream;
    FSize       : Int64;
    FFileDate   : tdatetime; // last modified
  public
    property FileName   : string read FFileName write FFileName;
    property Description: string read FDescription write FDescription;
    property Path       : string read FPath write FPath;
    property Content    : TMemoryStream read FContent write FContent;
    property Size       : Int64 read FSize write FSize;
    property FileDate   : tdatetime read FFileDate write FFileDate;
    /// <summary>Constructor, bereitet TMemoryStream im Feld FContent vor</summary>
    constructor Create;
    /// <summary>Destructor, leert den TMemorystrem im Feld FContent</summary>
    destructor Destroy; override;
    /// <summary>gibt den komplette Pfad der Datei inklusive Dateinamen als String zurück</summary>
    function ToString: string; override;
    procedure FetchContent(FtpConnection: TIdFTP);

  end;

  TFtpFileList = class(TObjectList<TFTPFile>)
  public
    constructor Create; overload;
    /// <summary>liest die Dateien eine FTP-Verzeichnisses aus und speichert diese in eine Liste</summary>
    procedure ParseRemoteDirectory(FtpConnection: TIdFTP; RemoteFolder: string; FtpFileList: TFtpFileList);
    function SearchForLocalFile(LocalFile: TLocalFile): boolean;
  end;

  TLocalFile = class
  private
    FFileName  : string;
    FPath      : string;
    FFileDate  : tdatetime;
    FSize      : Int64;
    FAttributes: Integer;
  public
    property FileName  : string read FFileName write FFileName;
    property Path      : string read FPath write FPath;
    property FileDate  : tdatetime read FFileDate write FFileDate;
    property Size      : Int64 read FSize write FSize;
    property Attributes: Integer read FAttributes write FAttributes;
    procedure SendContent(FtpConnection: TIdFTP);
  end;

  TLocalFileList = class(TObjectList<TLocalFile>)
  public
    constructor Create; overload;
    procedure ParseLocalDirectory(localPath: string; Result: TLocalFileList);
  end;

/// <summary>Constructor, bereitet TMemoryStream im Feld FContent vor</summary>
constructor TFTPFile.Create;
begin
  self.Content := TMemoryStream.Create; // supports all encodings
end;

/// <summary>Destructor, leert den TMemorystrem im Feld FContent</summary>
destructor TFTPFile.Destroy;
begin
  Content := nil;
  inherited;
end;

/// <summary>gibt den komplette Pfad der Datei inklusive Dateinamen als String zurück</summary>
function TFTPFile.ToString: string;
begin
  if (self.Path <> '') and not EndsStr('/', self.Path) then
    self.Path := self.Path + '/';
  Result := self.Path + self.FileName;
end;

procedure TFTPFile.FetchContent(FtpConnection: TIdFTP);
begin
  if FtpConnection.Connected then
  begin
    FtpConnection.Get(ToString, Content, False);
    Content.Seek(0, soFromBeginning);
  end;
end;

constructor TFtpFileList.Create;
begin
  inherited Create;
  OwnsObjects := True;
end;

procedure TFtpFileList.ParseRemoteDirectory(FtpConnection: TIdFTP; RemoteFolder: string; FtpFileList: TFtpFileList);

  procedure ParseDirectory(const RemoteFolder: string);
  var
    remoteFile       : TFTPFile;
    i                : Integer;
    delimiterlocation: Integer;
    Name             : string;
    RemoteFolderList : TStringList;
    folder           : string;
  begin
    RemoteFolderList := TStringList.Create;
    try
      FtpConnection.ChangeDir(RemoteFolder);
      FtpConnection.List(RemoteFolderList);
      for i := 0 to RemoteFolderList.Count - 1 do
      begin
        folder := RemoteFolderList[i];
        delimiterlocation := lastDelimiter(' ', folder);
        if delimiterlocation > 0 then
          name := copy(folder, delimiterlocation + 1, length(folder) - delimiterlocation)
        else
          name := folder;
        if folder[1] = 'd' then
          ParseDirectory(RemoteFolder + '/' + name)
        else
        begin
          remoteFile := TFTPFile.Create;
          try
            remoteFile.FileName := name;
            remoteFile.Description := folder;
            remoteFile.Path := RemoteFolder;
            remoteFile.Size := FtpConnection.Size(name);
            remoteFile.FileDate := FtpConnection.FileDate(name);
            FtpFileList.add(remoteFile);
          except
            FreeAndNil(remoteFile);
            raise;
          end;
        end;
      end;
    finally
      FreeAndNil(RemoteFolderList);
    end;
    if RemoteFolder <> '' then
      FtpConnection.ChangeDirUp;
  end;

begin
  if not FtpConnection.Connected then
    Exit;
  Clear;
  ParseDirectory(RemoteFolder);
end;

function TFtpFileList.SearchForLocalFile(LocalFile: TLocalFile): boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to self.Count-1 do
  begin
    if (self[i].FileName = LocalFile.FileName) and (self[i].Size = LocalFile.Size) and
        (self[i].FileDate >= LocalFile.FileDate) and (self[i].Path.IndexOf(LocalFile.Path.Replace('\','/',[rfReplaceAll])) > 0) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure SyncLocalToFTP(localfolder, ftpurl: string; ftpfolder: string; login, password: string);
var
  localFileList : TLocalFileList;
  remoteFileList: TFtpFileList;
  FtpConnection : TIdFTP;
  urlConnection : TIdURI;
  i             : integer;
begin
  FtpConnection := TIdFTP.Create(nil);
  urlConnection := TIdURI.Create(ftpurl);
  localFileList := TLocalFileList.Create;
  remoteFileList := TFtpFileList.Create;
  try
    FtpConnection.Host := urlConnection.Host;
    FtpConnection.port := strtointdef(urlConnection.port, 21);
    FtpConnection.UserName := login;
    FtpConnection.password := password;
    FtpConnection.AutoLogin := True;
    FtpConnection.Passive := True;
    writeln('Stelle Verbindung her zu: ' + login + ':' + password + '@' + ftpurl);
    FtpConnection.Connect;
    remoteFileList.ParseRemoteDirectory(FtpConnection, ftpfolder, remoteFileList);
    localFileList.ParseLocalDirectory(localfolder, localFileList);
    for i := 0 to localFileList.Count - 1 do
    begin
      if not remoteFileList.SearchForLocalFile(localFileList[i]) then
        writeln('fehlende Datei ermittelt: ' + localFilelist[i].Path +'\'+ localFileList[i].FileName);
        //          LocalFileList[i].SendContent(FtpConnection);
    end;
    writeln('Abgleich abgeschloßen');
  finally

  end;
end;

{ TLocalFile }

procedure TLocalFile.SendContent(FtpConnection: TIdFTP);
var
  filestream: TMemoryStream;
begin
  if FtpConnection.Connected then
  begin
    try
      filestream := TMemoryStream.Create;
      filestream.LoadFromFile(self.Path + self.FileName);
      FtpConnection.Put(filestream, self.FileName, False);
    finally
      filestream.Free
    end;
  end;
end;

{ TLocalFilesList }

constructor TLocalFileList.Create;
begin
  inherited Create;
  OwnsObjects := True;
end;

procedure TLocalFileList.ParseLocalDirectory(localPath: string; Result: TLocalFileList);
var
  Path     : string;
  rec      : TSearchRec;
  LocalFile: TLocalFile;
begin
  Path := IncludeTrailingPathDelimiter(localPath);
  if FindFirst(ExtractFilePath(ParamStr(0)) + Path + '*.*', faDirectory, rec) = 0 then
    try
      repeat
        if (rec.Name <> '.') and (rec.Name <> '..') then
        begin
          if rec.Attr <> faDirectory then
          begin
            try
              LocalFile := TLocalFile.Create;
              LocalFile.FileName := rec.Name;
              LocalFile.Path := localPath;
              LocalFile.FileDate := rec.TimeStamp;
              LocalFile.Size := rec.Size;
              Result.add(LocalFile);
            except
              FreeAndNil(LocalFile);
              raise;
            end;
          end;
          self.ParseLocalDirectory(Path + rec.Name, Result);
        end;
      until FindNext(rec) <> 0;
    finally
      sysutils.FindClose(rec);
    end;
end;

end.
