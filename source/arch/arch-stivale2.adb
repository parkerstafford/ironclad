--  arch-stivale2.adb: Stivale2 utilities.
--  Copyright (C) 2021 streaksu
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

with System.Machine_Code;     use System.Machine_Code;
with System.Storage_Elements; use System.Storage_Elements;
with Ada.Characters.Latin_1;  use Ada.Characters.Latin_1;
with System.Address_To_Access_Conversions;
with Arch.Wrappers;
with Memory.Virtual; use Memory.Virtual;

package body Arch.Stivale2 is

   Terminal_Enabled    : Boolean          := False;
   Terminal_Entrypoint : Physical_Address := Null_Address;

   function Get_Tag
     (Proto     : access Header;
     Identifier : Unsigned_64) return Virtual_Address is
      package Convert is new System.Address_To_Access_Conversions (Tag);

      Search_Address : Virtual_Address := Proto.Tags;
      Search_Tag     : access Tag;
   begin
      while Search_Address /= Null_Address loop
         Search_Address := Search_Address + Memory_Offset;
         Search_Tag     := Convert.To_Pointer (To_Address (Search_Address));
         if Search_Tag.Identifier = Identifier then
            return Search_Address;
         end if;
         Search_Address := Search_Tag.Next;
      end loop;
      return Null_Address;
   end Get_Tag;

   procedure Init_Terminal (Terminal : access Terminal_Tag) is
   begin
      Terminal_Enabled    := True;
      Terminal_Entrypoint := Terminal.TermWrite;
   end Init_Terminal;

   procedure Print_Terminal (Message : String) is
   begin
      Inner_Terminal (Message'Address, Message'Length);
   end Print_Terminal;

   procedure Print_Terminal (Message : Character) is
   begin
      Inner_Terminal (Message'Address, 1);
   end Print_Terminal;

   procedure Inner_Terminal (Message : System.Address; Length : Natural) is
   begin
      if not Terminal_Enabled then
         return;
      end if;

      declare
         Current_CR3 : constant Unsigned_64 := Wrappers.Read_CR3;
      begin
         --  Ensure we are using the kernel pagemap, as the lower half needs
         --  to be identity mapped, and only the kernel pagemap does that.
         if Kernel_Map /= null and then
            not Memory.Virtual.Is_Loaded (Kernel_Map.all)
         then
            Make_Active (Kernel_Map.all);
         end if;

         Asm ("push %%rdi" & LF & HT &
              "push %%rsi" & LF & HT &
              "call *%0"   & LF & HT &
              "pop %%rsi"  & LF & HT &
              "pop %%rdi",
              Inputs => (Physical_Address'Asm_Input ("m", Terminal_Entrypoint),
                         System.Address'Asm_Input   ("D",  Message),
                         Natural'Asm_Input          ("S",  Length)),
              Clobber  => "rax, rdx, rcx, r8, r9, r10, r11, memory",
              Volatile => True);

         if Kernel_Map /= null and then
            not Memory.Virtual.Is_Loaded (Kernel_Map.all)
         then
            Wrappers.Write_CR3 (Current_CR3);
         end if;
      end;
   end Inner_Terminal;
end Arch.Stivale2;
