--  arch-acpi.adb: ACPI parsing and scanning.
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

with Arch.Multiboot2;

package body Arch.ACPI is
   --  Globals to keep track of scanned tables.
   Use_XSDT     : Boolean         := False;
   Root_Address : Virtual_Address := Null_Address;

   function ScanTables return Boolean is
      Table : constant RSDP := Multiboot2.Get_RSDP;
   begin
      if Table.Signature /= "RSD PTR " then
         return False;
      end if;

      if Table.Revision >= 2 and Table.XSDT_Address /= Null_Address then
         Use_XSDT     := True;
         Root_Address := Physical_Address (Table.XSDT_Address);
      else
         Use_XSDT     := False;
         Root_Address := Physical_Address (Table.RSDT_Address);
      end if;

      Root_Address := Memory_Offset + Root_Address;
      return True;
   end ScanTables;

   function FindTable (Signature : SDT_Signature) return Virtual_Address is
      Root : RSDT with Address => To_Address (Root_Address);

      Limit : constant Natural := (Natural (Root.Header.Length)
         - Root.Header'Size / 8) / (if Use_XSDT then 8 else 4);
      Returned : Physical_Address := Null_Address;
   begin
      for I in 1 .. Limit loop
         if Use_XSDT then
            declare
               Entries : XSDT_Entries (1 .. Limit);
               for Entries'Address use Root.Entries'Address;
            begin
               Returned := Physical_Address (Entries (I));
            end;
         else
            declare
               Entries : RSDT_Entries (1 .. Limit);
               for Entries'Address use Root.Entries'Address;
            begin
               Returned := Physical_Address (Entries (I));
            end;
         end if;

         declare
            Test_Header : SDT_Header with Address => To_Address (Returned);
         begin
            if Test_Header.Signature = Signature then
               return Returned + Memory_Offset;
            end if;
         end;
      end loop;

      return Null_Address;
   end FindTable;
end Arch.ACPI;
