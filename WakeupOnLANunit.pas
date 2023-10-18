// This code was written by Yaron Gur, ChatGPT4 & some insights from this StackOverflow post (thank you Remy Lebeau):
// https://stackoverflow.com/questions/51649369/how-to-create-wake-on-lan-app-using-magic-packet-and-indy-in-delphi-xe6/51662208#51662208


// Use Indy, otherwise use WinSock
{.$DEFINE USEINDY}

// Enable to show error message
{.$TRACEDEBUG}

unit WakeupOnLANunit;

interface


procedure WakeOnLan(const AMACAddress: string); overload;
procedure WakeOnLan(const AMACAddress: string; WoL_Port : Integer); overload;
procedure WakeOnLan(const IPAddress, AMACAddress: string; WoL_Port : Integer); overload;

function  NormalizeMAC(const MACAddress: string): string;


implementation


uses
  Windows, SysUtils, Classes, Dialogs{$IFDEF USEINDY}, IdGlobal, IdUDPClient{$ELSE}, WinSock{$ENDIF};

const
  Default_WoL_PORT       = 9;
  Default_Broadcast_Addr = '255.255.255.255';


function NormalizeMAC(const MACAddress: string): string;
var
  I: Integer;
begin
  // Clean up the mac address of all undesired characters
  Result := '';
  for I := 1 to Length(MACAddress) do
  begin
    if MACAddress[I] in ['0'..'9', 'A'..'F', 'a'..'f'] then
      Result := Result + UpperCase(MACAddress[I]);
  end;
end;


procedure WakeOnLan(const AMACAddress: string);
begin
  WakeOnLan(Default_Broadcast_Addr,AMACAddress,Default_WoL_PORT);
end;


procedure WakeOnLan(const AMACAddress: string; WoL_Port : Integer);
begin
  WakeOnLan(Default_Broadcast_Addr,AMACAddress,WoL_PORT);
end;


{$IFDEF USEINDY}

procedure WakeOnLan(const IPAddress, AMACAddress: string; WoL_Port : Integer);
type
  TMacAddress = array [1..6] of Byte;
  TWakeRecord =
  packed record
    Waker : TMACAddress;
    MAC   : array [0..15] of TMacAddress;
  end;

var
  I          : Integer;
  WR         : TWakeRecord;
  MacAddress : TMacAddress;
  NormMAC    : String;
  UDP        : TIdUDPClient;

  {$IFDEF TRACEDEBUG}
  //S          : String;
  {$ENDIF}
begin
  FillChar(MacAddress, SizeOf(TMacAddress), 0);

  NormMAC := NormalizeMAC(Trim(AMACAddress));

  if Length(NormMac) = 12 then
  begin
    for I := 1 to 6 do MacAddress[I] := StrToIntDef('$' + Copy(NormMac, 1+((I-1)*2), 2), 0);

    {$IFDEF TRACEDEBUG}
    //S := '';
    //For I := 1 to 6 do S := S+IntToHex(MacAddress[I],2);
    //ShowMessage(
    //  'Original Mac Address : '+AMACAddress+#10#13+
    //  'Normalized MAC Address : '+NormMAC+#10#13+
    //  'Translated MAC Address : 0x'+S);
    {$ENDIF}

    for I := 1 to 6  do WR.Waker[I] := $FF;
    for I := 0 to 15 do WR.MAC[I]   := MacAddress;

    UDP := TIdUDPClient.Create(nil);
    try
      UDP.Host := IPAddress;
      UDP.Port := Wol_Port;
      UDP.IPVersion := Id_IPv4;
      UDP.BroadcastEnabled := True;
      Try
        UDP.SendBuffer(RawToBytes(WR, SizeOf(WR)));
        // UDP.Broadcast(RawToBytes(WR, SizeOf(WR)), WoL_Port); // Broadcast without IP
      except
        {$IFDEF TRACEDEBUG}On E : Exception do ShowMessage('Exception "'+E.Message+'" trying to broadcast wakeup signal');{$ENDIF}
      end;
    finally
      UDP.Free;
    end;
  end
    else
  Begin
    {$IFDEF TRACEDEBUG}ShowMessage('Invalid MAC address format');{$ENDIF}
  End;
end;

{$ELSE}

procedure WakeOnLan(const IPAddress, AMACAddress: string; WoL_Port : Integer);
var
  WSAData       : TWSAData;
  Addr          : TSockAddrIn;
  Sock          : TSocket;
  BroadcastFlag : BOOL;
  Packet        : Array[0..101] of Byte; // 6 bytes of FF followed by 16 repetitions of the MAC address
  MAC           : Array[0..5] of Byte;
  I, J          : Integer;
  SendFailed    : Boolean;
  MACAddress    : String;
begin
  MACAddress := NormalizeMAC(Trim(AMACAddress));

  If Length(MACAddress) = 12 then
  Begin
    // Initialize WinSock
    SendFailed := WSAStartup(MAKEWORD(2, 2), WSAData) <> 0;

    If SendFailed = False then
    Begin
      try
        // Create UDP socket
        Sock := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);

        SendFailed := Sock = INVALID_SOCKET;

        If SendFailed = False then
        Begin
          try
            // Enable broadcasting
            BroadcastFlag := True;

            SendFailed := setsockopt(Sock, SOL_SOCKET, SO_BROADCAST, @BroadcastFlag, SizeOf(BOOL)) = SOCKET_ERROR;

            If SendFailed = False then
            Begin
              // Build the Wake-on-LAN "Magic Packet"
              For I := 0 to 5 do Packet[I] := $FF;

              // Convert MAC string to bytes
              For I := 0 to 5 do MAC[I] := StrToInt('$' + Copy(MACAddress, 2 * I + 1, 2));

              For I := 1 to 16 do For J := 0 to 5 do Packet[I * 6 + J] := MAC[J];

              // Set up the broadcast address
              Addr.sin_family      := AF_INET;
              Addr.sin_port        := htons(WoL_Port);
              Addr.sin_addr.S_addr := inet_addr(PAnsiChar(AnsiString(IPAddress)));

              // Send the packet
              If sendto(Sock, Packet, SizeOf(Packet), 0, Addr, SizeOf(Addr)) = SOCKET_ERROR then
              Begin
                {$IFDEF TRACEDEBUG}ShowMessage('Failed to send Wake-on-LAN packet');{$ENDIF}
              End;
            End
              else
            Begin
              {$IFDEF TRACEDEBUG}ShowMessage('Failed to set socket to broadcast mode');{$ENDIF}
            End;
          finally
            closesocket(Sock);
          end;
        End
          else
        Begin
          {$IFDEF TRACEDEBUG}ShowMessage('Failed to create socket');{$ENDIF}
        End;
      finally
        WSACleanup;
      end;
    End
      else
    Begin
      {$IFDEF TRACEDEBUG}ShowMessage('Failed to initialize WinSock');{$ENDIF}
    End;
  End
    else
  Begin
    {$IFDEF TRACEDEBUG}ShowMessage('Invalid MAC Address');{$ENDIF}
  End;
end;

{$ENDIF}

end.

