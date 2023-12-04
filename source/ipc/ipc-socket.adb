--  ipc-socket.adb: Socket creation and management.
--  Copyright (C) 2023 streaksu
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.

with Ada.Unchecked_Deallocation;
with Scheduler;
with Networking.IPv4;
with Networking.IPv6;
with Networking.Interfaces;

package body IPC.Socket with SPARK_Mode => Off is
   procedure Free is new Ada.Unchecked_Deallocation (Socket, Socket_Acc);
   procedure Free is new Ada.Unchecked_Deallocation
      (Operation_Data, Operation_Data_Acc);

   function Create
      (Dom         : Domain;
       Typ         : DataType;
       Is_Blocking : Boolean := True) return Socket_Acc
   is
   begin
      case Dom is
         when IPv4 =>
            case Typ is
               when Raw =>
                  return new Socket'
                   (Mutex        => Lib.Synchronization.Unlocked_Semaphore,
                    Dom          => IPv4,
                    Typ          => Raw,
                    Is_Blocking  => Is_Blocking,
                    IPv4_Cached_Address => (others => 0),
                    IPv4_Cached_Port => 0);
               when others =>
                  return null;
            end case;
         when IPv6 =>
            case Typ is
               when Raw =>
                  return new Socket'
                   (Mutex        => Lib.Synchronization.Unlocked_Semaphore,
                    Dom          => IPv6,
                    Typ          => Raw,
                    Is_Blocking  => Is_Blocking,
                    IPv6_Cached_Address => (others => 0),
                    IPv6_Cached_Port => 0);
               when others =>
                  return null;
            end case;
         when UNIX =>
            case Typ is
               when Stream =>
                  return new Socket'
                   (Mutex          => Lib.Synchronization.Unlocked_Semaphore,
                    Dom            => UNIX,
                    Typ            => Stream,
                    Is_Listener    => False,
                    Is_Blocking    => Is_Blocking,
                    Connected      => null,
                    Pending_Accept => null,
                    Established    => null,
                    Data           => (others => 0),
                    Data_Length    => 0);
               when Datagram =>
                  return new Socket'
                   (Mutex            => Lib.Synchronization.Unlocked_Semaphore,
                    Dom              => UNIX,
                    Typ              => Datagram,
                    Is_Blocking      => Is_Blocking,
                    Simple_Connected => null,
                    Data             => (others => 0),
                    Data_Length      => 0);
               when Raw =>
                  return null;
            end case;
      end case;
   end Create;

   function Get_Domain (Sock : Socket_Acc) return Domain is
   begin
      return Sock.Dom;
   end Get_Domain;

   function Get_Type (Sock : Socket_Acc) return DataType is
   begin
      return Sock.Typ;
   end Get_Type;

   procedure Close (To_Close : in out Socket_Acc) is
   begin
      Lib.Synchronization.Seize (To_Close.Mutex);
      case To_Close.Dom is
         when IPv4 | IPv6 =>
            null;
         when UNIX =>
            Inner_UNIX_Close (To_Close);
      end case;
      Free (To_Close);
   end Close;

   function Is_Blocking (Sock : Socket_Acc) return Boolean is
      Result : Boolean;
   begin
      Lib.Synchronization.Seize (Sock.Mutex);
      Result := Sock.Is_Blocking;
      Lib.Synchronization.Release (Sock.Mutex);
      return Result;
   end Is_Blocking;

   procedure Set_Blocking (Sock : Socket_Acc; Is_Blocking : Boolean) is
   begin
      Lib.Synchronization.Seize (Sock.Mutex);
      Sock.Is_Blocking := Is_Blocking;
      Lib.Synchronization.Release (Sock.Mutex);
   end Set_Blocking;

   procedure Poll
      (Sock      : Socket_Acc;
       Can_Read  : out Boolean;
       Can_Write : out Boolean;
       Is_Broken : out Boolean;
       Is_Error  : out Boolean)
   is
   begin
      Lib.Synchronization.Seize (Sock.Mutex);
      case Sock.Dom is
         when IPv4 | IPv6 =>
            Can_Read  := False;
            Can_Write := False;
            Is_Broken := False;
            Is_Error  := False;
         when UNIX =>
            Inner_UNIX_Poll (Sock, Can_Read, Can_Write, Is_Broken, Is_Error);
      end case;
      Lib.Synchronization.Release (Sock.Mutex);
   end Poll;

   procedure Read
      (Sock      : Socket_Acc;
       Data      : out Devices.Operation_Data;
       Ret_Count : out Natural;
       Success   : out Socket_Status)
   is
   begin
      Lib.Synchronization.Seize (Sock.Mutex);
      case Sock.Dom is
         when IPv4 => Inner_IPv4_Read (Sock, Data, Ret_Count, Success);
         when IPv6 => Inner_IPv6_Read (Sock, Data, Ret_Count, Success);
         when UNIX => Inner_UNIX_Read (Sock, Data, Ret_Count, Success);
      end case;
      Lib.Synchronization.Release (Sock.Mutex);
   end Read;

   procedure Write
      (Sock      : Socket_Acc;
       Data      : Devices.Operation_Data;
       Ret_Count : out Natural;
       Success   : out Socket_Status)
   is
   begin
      Lib.Synchronization.Seize (Sock.Mutex);
      case Sock.Dom is
         when IPv4 => Inner_IPv4_Write (Sock, Data, Ret_Count, Success);
         when IPv6 => Inner_IPv6_Write (Sock, Data, Ret_Count, Success);
         when UNIX => Inner_UNIX_Write (Sock, Data, Ret_Count, Success);
      end case;
      Lib.Synchronization.Release (Sock.Mutex);
   end Write;

   function Shutdown
      (Sock             : Socket_Acc;
       Do_Receptions    : Boolean;
       Do_Transmissions : Boolean) return Boolean
   is
      Suc : Boolean;
   begin
      Lib.Synchronization.Seize (Sock.Mutex);
      case Sock.Dom is
         when IPv4 | IPv6 =>
            Suc := False;
         when UNIX =>
            Suc := Inner_UNIX_Shutdown (Sock, Do_Receptions, Do_Transmissions);
      end case;
      Lib.Synchronization.Release (Sock.Mutex);
      return Suc;
   end Shutdown;

   function Listen (Sock : Socket_Acc; Backlog : Natural) return Boolean is
      pragma Unreferenced (Backlog);
   begin
      Lib.Synchronization.Seize (Sock.Mutex);
      Sock.Is_Listener := True;
      Lib.Synchronization.Release (Sock.Mutex);
      return True;
   end Listen;

   procedure Accept_Connection
      (Sock        : Socket_Acc;
       Is_Blocking : Boolean := True;
       Result      : out Socket_Acc)
   is
      Path : String (1 .. 0);
      Len  : Natural;
   begin
      Lib.Synchronization.Seize (Sock.Mutex);
      case Sock.Dom is
         when IPv4 | IPv6 =>
            Result := null;
         when UNIX =>
            Accept_Connection (Sock, Is_Blocking, Path, Len, Result);
      end case;
      Lib.Synchronization.Release (Sock.Mutex);
   end Accept_Connection;
   ----------------------------------------------------------------------------
   procedure Get_Bound
      (Sock    : Socket_Acc;
       Addr    : out Networking.IPv4_Address;
       Port    : out Networking.IPv4_Port;
       Success : out Boolean)
   is
      pragma Unreferenced (Sock);
   begin
      Addr := (others => 0);
      Port := 0;
      Success := False;
   end Get_Bound;

   procedure Get_Peer
      (Sock    : Socket_Acc;
       Addr    : out Networking.IPv4_Address;
       Port    : out Networking.IPv4_Port;
       Success : out Boolean)
   is
      pragma Unreferenced (Sock);
   begin
      Addr := (others => 0);
      Port := 0;
      Success := False;
   end Get_Peer;

   function Bind
      (Sock : Socket_Acc;
       Addr : Networking.IPv4_Address;
       Port : Networking.IPv4_Port) return Boolean
   is
      pragma Unreferenced (Sock);
      pragma Unreferenced (Addr);
      pragma Unreferenced (Port);
   begin
      return False;
   end Bind;

   function Connect
      (Sock : Socket_Acc;
       Addr : Networking.IPv4_Address;
       Port : Networking.IPv4_Port) return Boolean
   is
   begin
      case Sock.Typ is
         when Raw =>
            Sock.IPv4_Cached_Address := Addr;
            Sock.IPv4_Cached_Port := Port;
            return True;
         when others =>
            return False;
      end case;
   end Connect;

   procedure Accept_Connection
      (Sock         : Socket_Acc;
       Is_Blocking  : Boolean := True;
       Peer_Address : out Networking.IPv4_Address;
       Peer_Port    : out Networking.IPv4_Port;
       Result       : out Socket_Acc)
   is
      pragma Unreferenced (Sock);
      pragma Unreferenced (Is_Blocking);
   begin
      Peer_Address := (others => 0);
      Peer_Port := 0;
      Result := null;
   end Accept_Connection;

   procedure Read
      (Sock      : Socket_Acc;
       Data      : out Devices.Operation_Data;
       Ret_Count : out Natural;
       Addr      : Networking.IPv4_Address;
       Port      : Networking.IPv4_Port;
       Success   : out Socket_Status)
   is
      pragma Unreferenced (Port);

      Succ : Boolean;
      Dev  : Devices.Device_Handle;
      Src  : Networking.IPv4_Address;
      Hdr_Size : constant Natural := Networking.IPv4.IPv4_Packet_Header'Size;
   begin
      case Sock.Typ is
         when Raw =>
            Networking.Interfaces.Get_Suitable_Interface (Addr, Dev);
            if Dev = Devices.Error_Handle then
               Data      := (others => 0);
               Ret_Count := 0;
               Success   := Would_Block;
               return;
            end if;
            Networking.Interfaces.Get_Interface_Address (Dev, Src);

            Devices.Read (Dev, 0, Data, Ret_Count, Succ);
            Data (Data'First .. Data'Last - (Hdr_Size / 8)) :=
               Data (Data'First + (Hdr_Size / 8) .. Data'Last);
            Ret_Count := Ret_Count - (Hdr_Size / 8);
            if Succ then
               Success := Plain_Success;
            else
               Success := Would_Block;
            end if;
         when others =>
            Data := (others => 0);
            Ret_Count := 0;
            Success := Is_Bad_Type;
      end case;
   end Read;

   procedure Write
      (Sock      : Socket_Acc;
       Data      : Devices.Operation_Data;
       Ret_Count : out Natural;
       Addr      : Networking.IPv4_Address;
       Port      : Networking.IPv4_Port;
       Success   : out Socket_Status)
   is
      pragma Unreferenced (Port);

      Succ : Boolean;
      Dev  : Devices.Device_Handle;
      Tmp_Data : Operation_Data_Acc;
      Src  : Networking.IPv4_Address;
      Hdr  : Networking.IPv4.IPv4_Packet_Header;

      Hdr_Data : Operation_Data (1 .. Hdr'Size / 8)
         with Import, Address => Hdr'Address;
   begin
      case Sock.Typ is
         when Raw =>
            Networking.Interfaces.Get_Suitable_Interface (Addr, Dev);
            if Dev = Devices.Error_Handle then
               Ret_Count := 0;
               Success   := Would_Block;
               return;
            end if;
            Networking.Interfaces.Get_Interface_Address (Dev, Src);

            Hdr := Networking.IPv4.Generate_Header (Src, Addr, Data'Length);
            Tmp_Data := new Operation_Data (1 .. Data'Length + (Hdr'Size / 8));
            Tmp_Data (1 .. Hdr_Data'Length) := Hdr_Data;
            Tmp_Data (Hdr_Data'Length + 1 .. Tmp_Data'Last) := Data;

            Devices.Write (Dev, 0, Tmp_Data.all, Ret_Count, Succ);
            Free (Tmp_Data);

            if Succ then
               Success := Plain_Success;
            else
               Success := Would_Block;
            end if;
         when others =>
            Ret_Count := 0;
            Success := Is_Bad_Type;
      end case;
   end Write;
   ----------------------------------------------------------------------------
   procedure Get_Bound
      (Sock    : Socket_Acc;
       Addr    : out Networking.IPv6_Address;
       Port    : out Networking.IPv6_Port;
       Success : out Boolean)
   is
      pragma Unreferenced (Sock);
   begin
      Addr := (others => 0);
      Port := 0;
      Success := False;
   end Get_Bound;

   procedure Get_Peer
      (Sock    : Socket_Acc;
       Addr    : out Networking.IPv6_Address;
       Port    : out Networking.IPv6_Port;
       Success : out Boolean)
   is
      pragma Unreferenced (Sock);
   begin
      Addr := (others => 0);
      Port := 0;
      Success := False;
   end Get_Peer;


   function Bind
      (Sock : Socket_Acc;
       Addr : Networking.IPv6_Address;
       Port : Networking.IPv6_Port) return Boolean
   is
      pragma Unreferenced (Sock);
      pragma Unreferenced (Addr);
      pragma Unreferenced (Port);
   begin
      return False;
   end Bind;

   function Connect
      (Sock : Socket_Acc;
       Addr : Networking.IPv6_Address;
       Port : Networking.IPv6_Port) return Boolean
   is
   begin
      case Sock.Typ is
         when Raw =>
            Sock.IPv6_Cached_Address := Addr;
            Sock.IPv6_Cached_Port := Port;
            return True;
         when others =>
            return False;
      end case;
   end Connect;

   procedure Accept_Connection
      (Sock         : Socket_Acc;
       Is_Blocking  : Boolean := True;
       Peer_Address : out Networking.IPv6_Address;
       Peer_Port    : out Networking.IPv6_Port;
       Result       : out Socket_Acc)
   is
      pragma Unreferenced (Sock);
      pragma Unreferenced (Is_Blocking);
   begin
      Peer_Address := (others => 0);
      Peer_Port := 0;
      Result := null;
   end Accept_Connection;

   procedure Read
      (Sock      : Socket_Acc;
       Data      : out Devices.Operation_Data;
       Ret_Count : out Natural;
       Addr      : Networking.IPv6_Address;
       Port      : Networking.IPv6_Port;
       Success   : out Socket_Status)
   is
      pragma Unreferenced (Port);

      Succ : Boolean;
      Dev  : Devices.Device_Handle;
      Src  : Networking.IPv6_Address;
      Hdr_Size : constant Natural := Networking.IPv6.IPv6_Packet_Header'Size;
   begin
      case Sock.Typ is
         when Raw =>
            Networking.Interfaces.Get_Suitable_Interface (Addr, Dev);
            if Dev = Devices.Error_Handle then
               Data      := (others => 0);
               Ret_Count := 0;
               Success   := Would_Block;
               return;
            end if;
            Networking.Interfaces.Get_Interface_Address (Dev, Src);

            Devices.Read (Dev, 0, Data, Ret_Count, Succ);
            Data (Data'First .. Data'Last - (Hdr_Size / 8)) :=
               Data (Data'First + (Hdr_Size / 8) .. Data'Last);
            Ret_Count := Ret_Count - (Hdr_Size / 8);
            if Succ then
               Success := Plain_Success;
            else
               Success := Would_Block;
            end if;
         when others =>
            Ret_Count := 0;
            Success   := Is_Bad_Type;
      end case;
   end Read;

   procedure Write
      (Sock      : Socket_Acc;
       Data      : Devices.Operation_Data;
       Ret_Count : out Natural;
       Addr      : Networking.IPv6_Address;
       Port      : Networking.IPv6_Port;
       Success   : out Socket_Status)
   is
      pragma Unreferenced (Port);

      Succ : Boolean;
      Dev  : Devices.Device_Handle;
      Tmp_Data : Operation_Data_Acc;
      Src  : Networking.IPv6_Address;
      Hdr  : Networking.IPv6.IPv6_Packet_Header;

      Hdr_Data : Operation_Data (1 .. Hdr'Size / 8)
         with Import, Address => Hdr'Address;
   begin
      case Sock.Typ is
         when Raw =>
            Networking.Interfaces.Get_Suitable_Interface (Addr, Dev);
            if Dev = Devices.Error_Handle then
               Ret_Count := 0;
               Success   := Would_Block;
               return;
            end if;
            Networking.Interfaces.Get_Interface_Address (Dev, Src);

            Hdr := Networking.IPv6.Generate_Header (Src, Addr, Data'Length);
            Tmp_Data := new Operation_Data (1 .. Data'Length + (Hdr'Size / 8));
            Tmp_Data (1 .. Hdr_Data'Length) := Hdr_Data;
            Tmp_Data (Hdr_Data'Length + 1 .. Tmp_Data'Last) := Data;

            Devices.Write (Dev, 0, Tmp_Data.all, Ret_Count, Succ);
            Free (Tmp_Data);

            if Succ then
               Success := Plain_Success;
            else
               Success := Would_Block;
            end if;
         when others =>
            Ret_Count := 0;
            Success   := Is_Bad_Type;
      end case;
   end Write;
   ----------------------------------------------------------------------------
   procedure Get_Bound
      (Sock    : Socket_Acc;
       Path    : out String;
       Length  : out Natural;
       Success : out Boolean)
   is
   begin
      Path    := (others => ' ');
      Length  := 0;
      Success := False;

      Lib.Synchronization.Seize (UNIX_Bound_Mutex);
      for Ent of UNIX_Bound_Sockets loop
         if Ent.Sock = Sock then
            Path (Path'First .. Path'First + Ent.Path_Len - 1) :=
               Ent.Path (1 .. Ent.Path_Len);
            Length  := Ent.Path_Len;
            Success := True;
            exit;
         end if;
      end loop;
      Lib.Synchronization.Release (UNIX_Bound_Mutex);
   end Get_Bound;

   procedure Get_Peer
      (Sock    : Socket_Acc;
       Path    : out String;
       Length  : out Natural;
       Success : out Boolean)
   is
   begin
      Path    := (others => ' ');
      Length  := 0;
      Success := False;

      Lib.Synchronization.Seize (UNIX_Bound_Mutex);
      for Ent of UNIX_Bound_Sockets loop
         if Ent.Sock = Sock.Established then
            if Path'Length >= Ent.Path_Len then
               Path (Path'First .. Path'First + Ent.Path_Len - 1) :=
                  Ent.Path (1 .. Ent.Path_Len);
            else
               Path := Ent.Path (1 .. Path'Length);
            end if;
            Length  := Ent.Path_Len;
            Success := True;
            exit;
         end if;
      end loop;
      Lib.Synchronization.Release (UNIX_Bound_Mutex);
   end Get_Peer;

   function Bind (Sock : Socket_Acc; Path : String) return Boolean is
      Success : Boolean := False;
   begin
      if Path'Length = 0 or Path'Length > Bind_Path_Max then
         return False;
      end if;

      Lib.Synchronization.Seize (UNIX_Bound_Mutex);

      for Ent of UNIX_Bound_Sockets loop
         if Ent.Sock = Sock then
            goto Cleanup;
         end if;
      end loop;
      for Ent of UNIX_Bound_Sockets loop
         if Ent.Sock = null then
            Ent.Sock := Sock;
            Ent.Path (1 .. Path'Length) := Path;
            Ent.Path_Len := Path'Length;
            Success := True;
            goto Cleanup;
         end if;
      end loop;

   <<Cleanup>>
      Lib.Synchronization.Release (UNIX_Bound_Mutex);
      return Success;
   end Bind;

   function Connect (Sock : Socket_Acc; Path : String) return Boolean is
      To_Connect : Socket_Acc;
      Success    : Boolean;
   begin
      Lib.Synchronization.Seize (UNIX_Bound_Mutex);

      To_Connect := Get_Bound (Path);
      if To_Connect = null then
         Success := False;
         goto End_Return;
      end if;
      case Sock.Typ is
         when Stream =>
            Sock.Connected := To_Connect;
            loop
               if To_Connect.Pending_Accept = null then
                  To_Connect.Pending_Accept := Sock;
                  exit;
               end if;
               Scheduler.Yield_If_Able;
            end loop;
            loop
               exit when Sock.Pending_Accept /= null;
               Scheduler.Yield_If_Able;
            end loop;
         when others =>
            Sock.Simple_Connected := To_Connect;
      end case;

      Success := True;

   <<End_Return>>
      Lib.Synchronization.Release (UNIX_Bound_Mutex);
      return Success;
   end Connect;

   procedure Accept_Connection
      (Sock                : Socket_Acc;
       Is_Blocking         : Boolean := True;
       Peer_Address        : out String;
       Peer_Address_Length : out Natural;
       Result              : out Socket_Acc)
   is
   begin
      Peer_Address        := (others => ' ');
      Peer_Address_Length := 0;
      Result              := null;

      Lib.Synchronization.Seize (Sock.Mutex);

      if Sock.Is_Listener then
         loop
            if Sock.Pending_Accept /= null then
               Result := Create
                  (Sock.Pending_Accept.Dom,
                   Sock.Pending_Accept.Typ,
                   Is_Blocking);

               Sock.Pending_Accept.Established := Result;
               Sock.Pending_Accept.Pending_Accept := Result;
               Result.Established := Sock;
               --  Result.Pending_Accept := Sock;
               Result.Pending_Accept := Sock.Pending_Accept;
               Sock.Pending_Accept := null;
               exit;
            end if;
            exit when not Sock.Is_Blocking;
            Scheduler.Yield_If_Able;
         end loop;
      end if;

      Lib.Synchronization.Release (Sock.Mutex);
   end Accept_Connection;

   procedure Read
      (Sock      : Socket_Acc;
       Data      : out Devices.Operation_Data;
       Ret_Count : out Natural;
       Path      : String;
       Success   : out Socket_Status)
   is
      Discard : Boolean;
      Temp : constant Socket_Acc := Sock.Simple_Connected;
   begin
      Discard := Connect (Sock, Path);
      Inner_UNIX_Read (Sock, Data, Ret_Count, Success);
      Sock.Simple_Connected := Temp;
   end Read;

   procedure Write
      (Sock      : Socket_Acc;
       Data      : Devices.Operation_Data;
       Ret_Count : out Natural;
       Path      : String;
       Success   : out Socket_Status)
   is
      Discard : Boolean;
      Temp : constant Socket_Acc := Sock.Simple_Connected;
   begin
      Discard := Connect (Sock, Path);
      Inner_UNIX_Write (Sock, Data, Ret_Count, Success);
      Sock.Simple_Connected := Temp;
   end Write;
   ----------------------------------------------------------------------------
   procedure Inner_IPv4_Read
      (Sock      : Socket_Acc;
       Data      : out Devices.Operation_Data;
       Ret_Count : out Natural;
       Success   : out Socket_Status)
   is
   begin
      Read
         (Sock      => Sock,
          Data      => Data,
          Ret_Count => Ret_Count,
          Addr      => Sock.IPv4_Cached_Address,
          Port      => Sock.IPv4_Cached_Port,
          Success   => Success);
   end Inner_IPv4_Read;

   procedure Inner_IPv4_Write
      (Sock      : Socket_Acc;
       Data      : Devices.Operation_Data;
       Ret_Count : out Natural;
       Success   : out Socket_Status)
   is
   begin
      Write
         (Sock      => Sock,
          Data      => Data,
          Ret_Count => Ret_Count,
          Addr      => Sock.IPv4_Cached_Address,
          Port      => Sock.IPv4_Cached_Port,
          Success   => Success);
   end Inner_IPv4_Write;
   ----------------------------------------------------------------------------
   procedure Inner_IPv6_Read
      (Sock      : Socket_Acc;
       Data      : out Devices.Operation_Data;
       Ret_Count : out Natural;
       Success   : out Socket_Status)
   is
   begin
      Read
         (Sock      => Sock,
          Data      => Data,
          Ret_Count => Ret_Count,
          Addr      => Sock.IPv6_Cached_Address,
          Port      => Sock.IPv6_Cached_Port,
          Success   => Success);
   end Inner_IPv6_Read;

   procedure Inner_IPv6_Write
      (Sock      : Socket_Acc;
       Data      : Devices.Operation_Data;
       Ret_Count : out Natural;
       Success   : out Socket_Status)
   is
   begin
      Write
         (Sock      => Sock,
          Data      => Data,
          Ret_Count => Ret_Count,
          Addr      => Sock.IPv6_Cached_Address,
          Port      => Sock.IPv6_Cached_Port,
          Success   => Success);
   end Inner_IPv6_Write;
   ----------------------------------------------------------------------------
   function Get_Bound (Path : String) return Socket_Acc is
   begin
      for Ent of UNIX_Bound_Sockets loop
         if Ent.Sock /= null and then Ent.Path (1 .. Ent.Path_Len) = Path then
            return Ent.Sock;
         end if;
      end loop;
      return null;
   end Get_Bound;

   procedure Inner_UNIX_Close (To_Close : Socket_Acc) is
   begin
      Lib.Synchronization.Seize (UNIX_Bound_Mutex);
      for Ent of UNIX_Bound_Sockets loop
         if Ent.Sock = To_Close then
            Ent.Sock := null;
            exit;
         end if;
      end loop;
      Lib.Synchronization.Release (UNIX_Bound_Mutex);
   end Inner_UNIX_Close;

   procedure Inner_UNIX_Read
      (Sock      : Socket_Acc;
       Data      : out Devices.Operation_Data;
       Ret_Count : out Natural;
       Success   : out Socket_Status)
   is
   begin
   <<Retry>>
      if Sock.Is_Blocking then
         while Sock.Data_Length = 0 loop
            Scheduler.Yield_If_Able;
         end loop;
      end if;

      case Sock.Typ is
         when Stream =>
            if Sock.Is_Listener or Sock.Pending_Accept = null then
               Data      := (others => 0);
               Ret_Count := 0;
               Success   := Is_Bad_Type;
               return;
            elsif Sock.Data_Length = 0 then
               if Sock.Is_Blocking then
                  goto Retry;
               else
                  Data      := (others => 0);
                  Ret_Count := 0;
                  Success   := Would_Block;
                  return;
               end if;
            end if;

            if Sock.Data_Length <= Data'Length then
               Data (1 .. Sock.Data_Length) :=
                  Sock.Data (1 .. Sock.Data_Length);
               Ret_Count        := Sock.Data_Length;
               Sock.Data_Length := 0;
            else
               Data             := Sock.Data (1 .. Data'Length);
               Sock.Data_Length := Sock.Data_Length - Data'Length;
               Ret_Count        := Data'Length;
            end if;
            Success := Plain_Success;
         when others =>
            if Sock.Data_Length <= Data'Length then
               Data (1 .. Sock.Data_Length) :=
                  Sock.Data (1 .. Sock.Data_Length);
               Ret_Count := Sock.Data_Length;
               Success   := Plain_Success;
            else
               Ret_Count := 0;
               Success   := Would_Block;
            end if;
      end case;
   end Inner_UNIX_Read;

   procedure Inner_UNIX_Write
      (Sock      : Socket_Acc;
       Data      : Devices.Operation_Data;
       Ret_Count : out Natural;
       Success   : out Socket_Status)
   is
   begin
      case Sock.Typ is
         when Stream =>
            if Sock.Is_Listener or Sock.Pending_Accept = null then
               Ret_Count := 0;
               Success   := Is_Bad_Type;
               return;
            end if;

            Sock.Pending_Accept.Data (1 .. Data'Length) := Data;
            Sock.Pending_Accept.Data_Length := Data'Length;
            Ret_Count := Data'Length;
            Success   := Plain_Success;
         when others =>
            if Sock.Simple_Connected.Data_Length = 0 then
               Sock.Simple_Connected.Data (1 .. Data'Length) := Data;
               Sock.Simple_Connected.Data_Length := Data'Length;
               Ret_Count := Data'Length;
               Success   := Plain_Success;
            else
               Ret_Count := 0;
               Success   := Would_Block;
            end if;
      end case;
   end Inner_UNIX_Write;

   procedure Inner_UNIX_Poll
      (Sock      : Socket_Acc;
       Can_Read  : out Boolean;
       Can_Write : out Boolean;
       Is_Broken : out Boolean;
       Is_Error  : out Boolean)
   is
   begin
      case Sock.Typ is
         when Stream =>
            if Sock.Is_Listener then
               Can_Read  := True;
               Can_Write := True;
               Is_Broken := False;
               Is_Error  := False;
            else
               Can_Read  := Sock.Data_Length /= 0;
               Can_Write := Sock.Pending_Accept /= null and then
                            Sock.Pending_Accept.Data_Length /=
                            Sock.Pending_Accept.Data'Length;
               Is_Broken := Sock.Pending_Accept = null;
               Is_Error  := False;
            end if;
         when others =>
            Can_Read  := Sock.Data_Length      /= 0;
            Can_Write := Sock.Simple_Connected /= null;
            Is_Broken := Sock.Simple_Connected = null;
            Is_Error  := False;
      end case;
   end Inner_UNIX_Poll;

   function Inner_UNIX_Shutdown
      (Sock             : Socket_Acc;
       Do_Receptions    : Boolean;
       Do_Transmissions : Boolean) return Boolean
   is
      pragma Unreferenced (Do_Receptions);
      pragma Unreferenced (Do_Transmissions);
   begin
      if Sock.Established /= null then
         Sock.Established.Established := null;
         Sock.Established             := null;
      end if;
      return True;
   end Inner_UNIX_Shutdown;
end IPC.Socket;
